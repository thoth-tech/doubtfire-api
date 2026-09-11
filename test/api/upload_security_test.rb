# frozen_string_literal: true

require 'test_helper'
require 'zip'

# FILE-S01 – Upload Authorisation and Abuse Tests
#
# Exercises the FILE-S01 controls that can be verified deterministically in the
# API test environment. The threat model and findings disposition in
# docs/security/ describe the covered controls and the deliberately open gaps.
#
#  1.  Direct API upload without using the frontend
#  2.  Access to another student's or project's attachment
#  3.  Misleading extensions and mismatched MIME types
#  4.  File-signature mismatch where the policy uses signature checks
#  5.  Empty, oversized, malformed, and unsupported files
#  6.  Path traversal, control characters, and unusual Unicode filenames
#  7.  Download headers and active-content rendering behaviour
#  8.  Macro-enabled documents, archives, encrypted files
#  9.  Sequential duplicate upload and archive resource-exhaustion controls
# 10.  Cleanup before staging for rejected uploads

class UploadSecurityTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::TestFileHelper
  include TestHelpers::AuthHelper

  # ─────────────────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────────────────

  # Build a minimal TaskDefinition with configurable upload requirements.
  def create_task_definition(unit:, upload_requirements: [{ 'key' => 'file0', 'name' => 'Submission', 'type' => 'code' }])
    TaskDefinition.create!(
      unit_id: unit.id,
      tutorial_stream: unit.tutorial_streams.first,
      name: 'Security Test Task',
      description: 'Security Test Task',
      weighting: 4,
      target_grade: 0,
      start_date: Time.zone.now - 2.weeks,
      target_date: Time.zone.now + 1.week,
      abbreviation: "SecTask#{SecureRandom.hex(4)}",
      restrict_status_updates: false,
      upload_requirements: upload_requirements,
      plagiarism_warn_pct: 0.8,
      is_graded: false,
      max_quality_pts: 0
    )
  end

  # Create a Tempfile with given content and extension, yield it, then clean up.
  def with_tempfile(extension, content = 'dummy content', binary: false)
    Tempfile.create(['sec_test', extension]) do |f|
      f.binmode if binary
      f.write(content)
      f.flush
      yield f
    end
  end

  # Post a submission to the API with an arbitrary Rack::Test::UploadedFile.
  # Uses the same hash structure that scoop_files expects (file is a Hash with
  # :filename, :type, :name, :tempfile keys via Rack multipart parsing).
  def post_submission(project, task_def, uploaded_file, trigger: 'ready_for_feedback')
    data = { trigger: trigger, file0: uploaded_file }
    post "/api/projects/#{project.id}/task_def_id/#{task_def.id}/submission", data
  end

  def upload_storage_entries
    roots = [
      File.join(Dir.tmpdir, 'doubtfire', 'new'),
      FileHelper.student_work_dir(:new, nil, false),
      FileHelper.student_work_dir(:in_process, nil, false)
    ]

    roots.flat_map do |root|
      next [] unless Dir.exist?(root)

      Dir.glob(File.join(root, '**', '*'))
    end.sort
  end

  def capture_rails_logs(level: Logger::DEBUG)
    output = StringIO.new
    test_logger = Logger.new(output)
    test_logger.level = level
    original_logger = Rails.logger
    Rails.logger = test_logger

    yield
    output.string
  ensure
    Rails.logger = original_logger if defined?(original_logger) && original_logger
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 1. Direct API upload without using the frontend
  #    The backend must enforce authentication and authorisation regardless of
  #    whether a frontend-originated cookie/CSRF token is present.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'unauthenticated direct API upload is rejected with 419' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)

    # No auth header – simulate a raw API call with no session at all.
    with_tempfile('.py', "print('hello')") do |f|
      post_submission(project, td, Rack::Test::UploadedFile.new(f.path, 'text/plain'))
    end

    assert_equal 419, last_response.status,
                 'Expected 419 (authentication required) for unauthenticated direct API upload'
  ensure
    unit.destroy
  end

  test 'authenticated direct API upload succeeds for own project' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)

    add_auth_header_for(user: project.student)

    with_tempfile('.py', "print('hello')") do |f|
      post_submission(project, td, Rack::Test::UploadedFile.new(f.path, 'text/plain'))
    end

    assert_equal 201, last_response.status,
                 'Expected 201 for a valid authenticated direct API upload'
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 2. Access to another student's or project's attachment
  #    A student must not be able to submit on behalf of another project, nor
  #    download another student's submission PDF.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'student cannot submit to another student\'s project' do
    unit      = FactoryBot.create(:unit, student_count: 2, task_count: 0)
    projects  = unit.active_projects
    project_a = projects.first
    project_b = projects.second
    td        = create_task_definition(unit: unit)

    # Authenticate as student A but post to project B's endpoint.
    add_auth_header_for(user: project_a.student)

    side_effects_before = {
      tasks: Task.count,
      submissions: TaskSubmission.count,
      jobs: AcceptSubmissionJob.jobs.size,
      storage: upload_storage_entries
    }

    with_tempfile('.py', "print('owned')") do |f|
      post_submission(project_b, td, Rack::Test::UploadedFile.new(f.path, 'text/plain'))
    end

    assert_equal 401, last_response.status,
                 'Expected the current submission API contract to return 401 for a cross-project POST'
    assert_match(/not authorised to submit task/i, last_response.body)
    assert_equal side_effects_before[:tasks], Task.count,
                 'Rejected cross-project POST must not create a task'
    assert_equal side_effects_before[:submissions], TaskSubmission.count,
                 'Rejected cross-project POST must not create a submission row'
    assert_equal side_effects_before[:jobs], AcceptSubmissionJob.jobs.size,
                 'Rejected cross-project POST must not enqueue submission processing'
    assert_equal side_effects_before[:storage], upload_storage_entries,
                 'Rejected cross-project POST must not write submission files'
  ensure
    unit.destroy
  end

  test 'student cannot download another student\'s submission PDF' do
    unit      = FactoryBot.create(:unit, student_count: 2, task_count: 0)
    projects  = unit.active_projects
    project_a = projects.first
    project_b = projects.second
    td        = create_task_definition(unit: unit)

    # Authenticate as student B and attempt to fetch project A's submission.
    add_auth_header_for(user: project_b.student)

    get "/api/projects/#{project_a.id}/task_def_id/#{td.id}/submission"

    assert_equal 401, last_response.status,
                 'Expected the current submission API contract to return 401 for a cross-project GET'
    assert_match(/not authorised to get task/i, last_response.body)
  ensure
    unit.destroy
  end

  test 'student cannot access another student\'s submission history' do
    unit      = FactoryBot.create(:unit, student_count: 2, task_count: 0)
    projects  = unit.active_projects
    project_a = projects.first
    project_b = projects.second
    td        = create_task_definition(unit: unit)

    add_auth_header_for(user: project_b.student)

    get "/api/projects/#{project_a.id}/task_def_id/#{td.id}/submission_histories"

    assert_equal 401, last_response.status,
                 'Expected the current history API contract to return 401 for cross-project access'
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 3. Misleading extensions and mismatched MIME types
  #    A file whose extension says .pdf but whose content (MIME) is something
  #    else must be rejected by the server-side MIME sniff.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'rejects file with PDF extension but plain-text content' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(
      unit: unit,
      upload_requirements: [{ 'key' => 'file0', 'name' => 'Report', 'type' => 'document' }]
    )

    add_auth_header_for(user: project.student)

    # Actual content is plain text, but we claim .pdf and application/pdf.
    with_tempfile('.pdf', 'This is not a PDF at all') do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'application/pdf', true)
      post_submission(project, td, uploaded)
    end

    assert_equal 403, last_response.status,
                 'Expected MIME validation to reject PDF extension with non-PDF content'
    assert_match(/invalid file MIME type/i, last_response.body)
  ensure
    unit.destroy
  end

  test 'rejects executable disguised with .txt extension' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)

    add_auth_header_for(user: project.student)

    # ELF magic bytes – a Linux executable masquerading as a text file.
    elf_magic = "\x7fELF\x02\x01\x01\x00#{"\x00" * 8}"
    with_tempfile('.txt', elf_magic, binary: true) do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'text/plain', true)
      post_submission(project, td, uploaded)
    end

    assert_equal 403, last_response.status,
                 'Expected MIME validation to reject ELF binary with .txt extension'
    assert_match(/invalid file MIME type/i, last_response.body)
  ensure
    unit.destroy
  end

  test 'rejects PHP script with image extension' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(
      unit: unit,
      upload_requirements: [{ 'key' => 'file0', 'name' => 'Image', 'type' => 'image' }]
    )

    add_auth_header_for(user: project.student)

    php_payload = '<?php system($_GET["cmd"]); ?>'
    with_tempfile('.jpg', php_payload) do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'image/jpeg', true)
      post_submission(project, td, uploaded)
    end

    assert_equal 403, last_response.status,
                 'Expected MIME validation to reject PHP payload with .jpg extension'
    assert_match(/invalid file MIME type/i, last_response.body)
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 4. File-signature mismatch where the policy uses signature checks
  #    FileHelper uses FileMagic (libmagic) to detect the actual MIME type.
  #    Files whose magic bytes disagree with the declared type must be rejected.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'accept_file rejects file whose magic bytes mismatch the kind' do
    # Use FileHelper directly to confirm the signature check, independent of
    # the API layer.
    result = with_tempfile('.pdf', "PK\x03\x04rest of zip", binary: true) do |f|
      FileHelper.accept_file(
        { filename: 'report.pdf', 'tempfile' => f },
        'Report',
        'document'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject a file whose magic bytes are ZIP but kind is document'
    assert_includes result[:msg].downcase, 'mime',
                    'Expected rejection message to mention MIME type mismatch'
  end

  test 'accept_file rejects HTML file presented as an image' do
    html_content = '<html><body><script>alert(1)</script></body></html>'
    result = with_tempfile('.png', html_content) do |f|
      FileHelper.accept_file(
        { filename: 'photo.png', 'tempfile' => f },
        'Photo',
        'image'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject HTML content submitted as an image'
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 5. Empty, oversized, malformed, and unsupported files
  # ─────────────────────────────────────────────────────────────────────────────

  test 'empty file is rejected by MIME validation' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)

    add_auth_header_for(user: project.student)

    with_tempfile('.py', '') do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'text/plain', true)
      post_submission(project, td, uploaded)
    end

    assert_equal 403, last_response.status,
                 "Expected MIME validation to reject an empty file, got: #{last_response.body}"
    assert_match(/invalid file MIME type/i, last_response.body)
  ensure
    unit.destroy
  end

  test 'rejects file exceeding the configured max_file_size' do
    original_max = Doubtfire::Application.config.max_file_size
    Doubtfire::Application.config.max_file_size = 1_024 # 1 KB

    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)

    add_auth_header_for(user: project.student)

    with_tempfile('.py', 'x' * 2_048) do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'text/plain', true)
      post_submission(project, td, uploaded)
    end

    assert_equal 403, last_response.status,
                 'Expected upload validation to reject a file exceeding max_file_size'
    assert_match(/exceeds the \d+MB file limit/i, last_response.body)
  ensure
    unit.destroy
    Doubtfire::Application.config.max_file_size = original_max
  end

  test 'rejects malformed / corrupted PDF' do
    result = File.open(Rails.root.join('test_files/submissions/corrupted.pdf')) do |f|
      FileHelper.accept_file(
        { filename: 'corrupted.pdf', 'tempfile' => f },
        'Report',
        'document'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject a corrupted PDF'
    assert_match(/corrupt/i, result[:msg])
  end

  test 'rejects unsupported file extension' do
    result = with_tempfile('.exe', "MZ#{"\x90" * 10}", binary: true) do |f|
      FileHelper.accept_file(
        { filename: 'malware.exe', 'tempfile' => f },
        'Code',
        'code'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject an .exe file'
    assert_includes result[:msg].downcase, 'extension'
  end

  test 'rejects malformed zip file' do
    result = Tempfile.create(['bad', '.zip']) do |f|
      f.write('this is not a zip file at all')
      f.flush
      FileHelper.accept_file(
        { filename: 'submission.zip', 'tempfile' => f },
        'Archive',
        'zip'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject a malformed zip file'
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 6. Path traversal, control characters, and unusual Unicode filenames
  # ─────────────────────────────────────────────────────────────────────────────

  test 'rejects zip containing path traversal entry' do
    Tempfile.create(['traversal', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('../../../etc/passwd') { |io| io.write('root:x:0:0') }
      end

      result = FileHelper.accept_file(
        { filename: 'submission.zip', 'tempfile' => zip_file },
        'Archive',
        'zip'
      )

      assert_not result[:accepted],
                 'Expected rejection for zip with path traversal entry'
      assert_match(/unsafe path/i, result[:msg])
    end
  end

  test 'sanitized_filename strips path separators and control characters' do
    dangerous_names = [
      "../../../etc/passwd",
      "..\\..\\windows\\system32\\cmd.exe",
      "file\x00name.txt",          # null byte
      "file\x01name.txt",          # SOH control char
      "file\nname.txt",            # newline
      "file\rname.txt"             # carriage return
    ]

    dangerous_names.each do |name|
      sanitized = FileHelper.sanitized_filename(name)

      assert_not_includes sanitized, '..', "sanitized_filename should remove '..' from '#{name}'"
      assert_not_includes sanitized, '/', "sanitized_filename should remove '/' from '#{name}'"
      assert_not_includes sanitized, '\\', "sanitized_filename should remove backslash from '#{name}'"
      assert_not_includes sanitized, "\x00", "sanitized_filename should remove null byte from '#{name}'"
      # Control characters (ASCII 0-31) should be stripped.
      assert_equal sanitized, sanitized.gsub(/[[:cntrl:]]/, ''),
                   "sanitized_filename should remove control characters from '#{name}'"
    end
  end

  test 'sanitized_path does not allow traversal outside base directory' do
    traversal_paths = [
      ['../secret', 'data'],
      ['../../etc', 'passwd'],
      ['valid', '../escape']
    ]

    traversal_paths.each do |parts|
      result = FileHelper.sanitized_path(*parts)
      assert_no_match(/\.\./, result,
                      "sanitized_path should not contain '..' for input #{parts.inspect}")
    end
  end

  test 'submission is accepted with a valid Unicode filename' do
    # Unicode filenames that are unusual but legitimate should not crash the
    # system, and accepted files should be stored safely.
    unicode_name = "提出物_\u4E2D\u6587_file.py"
    unit         = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project      = unit.active_projects.first
    td           = create_task_definition(unit: unit)

    add_auth_header_for(user: project.student)

    with_tempfile('.py', "print('hello')") do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'text/plain', false, original_filename: unicode_name)
      post_submission(project, td, uploaded)
    end

    assert_equal 201, last_response.status,
                 "Expected a valid Unicode filename to be accepted, got: #{last_response.body}"
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 7. Download headers and active-content rendering behaviour
  #    Submission PDFs must be served with Content-Disposition: attachment and a
  #    safe Content-Type so browsers do not execute them inline.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'submission download is served as attachment not inline' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(
      unit: unit,
      upload_requirements: [{ 'key' => 'file0', 'name' => 'Report', 'type' => 'document' }]
    )

    add_auth_header_for(user: project.student)

    data = with_file('test_files/submissions/valid.pdf', 'application/pdf',
                     { trigger: 'ready_for_feedback' })
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data
    assert_equal 201, last_response.status, last_response.body

    get "/api/projects/#{project.id}/task_def_id/#{td.id}/submission?as_attachment=true"

    content_disp = last_response.headers['Content-Disposition'].to_s
    assert_match(/attachment/i, content_disp,
                 'Submission download should use Content-Disposition: attachment when requested')
  ensure
    unit.destroy
  end

  test 'submission endpoint returns application/pdf content type' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(
      unit: unit,
      upload_requirements: [{ 'key' => 'file0', 'name' => 'Report', 'type' => 'document' }]
    )

    add_auth_header_for(user: project.student)

    data = with_file('test_files/submissions/valid.pdf', 'application/pdf',
                     { trigger: 'ready_for_feedback' })
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data
    assert_equal 201, last_response.status, last_response.body

    get "/api/projects/#{project.id}/task_def_id/#{td.id}/submission"

    content_type = last_response.headers['Content-Type'].to_s
    assert_match(%r{application/pdf}, content_type,
                 'Submission GET should return application/pdf, not text/html or similar')
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 8. Macro-enabled documents, archives, and encrypted files
  # ─────────────────────────────────────────────────────────────────────────────

  test 'rejects encrypted PDF' do
    result = File.open(Rails.root.join('test_files/submissions/encrypted.pdf')) do |f|
      FileHelper.accept_file(
        { filename: 'encrypted.pdf', 'tempfile' => f },
        'Report',
        'document'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject an encrypted PDF'
    assert_match(/encrypt/i, result[:msg])
  end

  test 'rejects unsupported Word document extension' do
    # Production accepts PDF only for document uploads. DOCX is not a known
    # extension and no conversion path runs from FileHelper.accept_file.
    with_tempfile('.docx', "PK\x03\x04fake docx content", binary: true) do |f|
      result = FileHelper.accept_file(
        { filename: 'report.docx', 'tempfile' => f },
        'Report',
        'document'
      )

      assert_not result[:accepted], 'Expected DOCX to be rejected for document uploads'
      assert_equal 'invalid file extension.', result[:msg]
    end
  end

  test 'rejects zip containing nested archive' do
    Tempfile.create(['nested', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('src/vendor.zip') { |io| io.write("PK#{"\x00" * 10}") }
      end

      result = FileHelper.accept_file(
        { filename: 'submission.zip', 'tempfile' => zip_file },
        'Archive',
        'zip'
      )

      assert_not result[:accepted],
                 'Expected rejection for zip containing a nested archive'
      assert_match(/nested/i, result[:msg])
    end
  end

  test 'rejects .xlsm (macro-enabled Excel) file submitted as a document' do
    # .xlsm is not in the allowed extension list for 'document' kind.
    result = with_tempfile('.xlsm', "PK\x03\x04fake xlsm", binary: true) do |f|
      FileHelper.accept_file(
        { filename: 'macro_sheet.xlsm', 'tempfile' => f },
        'Spreadsheet',
        'document'
      )
    end

    assert_not result[:accepted],
               'Expected accept_file to reject a macro-enabled spreadsheet as a document'
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 9. Sequential duplicate-upload / storage-exhaustion controls
  #    The zip abuse defences limit per-archive resource use. The API also
  #    rejects a later duplicate while the first accepted upload is queued.
  #    A true simultaneous race requires a separate multi-connection test.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'zip compression-ratio limit is enforced' do
    # A zip that compresses highly repeated data is a potential zip bomb.
    original_max    = Doubtfire::Application.config.max_file_size
    original_ratio  = Doubtfire::Application.config.zip_compression_ratio_limit
    Doubtfire::Application.config.max_file_size = 100_000_000
    Doubtfire::Application.config.zip_compression_ratio_limit = 5

    Tempfile.create(['bomb', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        # Write 1 MB of all-zeroes – compresses to ~1 KB, ratio >> 5.
        zip.get_output_stream('zeros.txt') { |io| io.write("\x00" * 1_000_000) }
      end

      result = FileHelper.validate_zip_upload(zip_file.path, 'bomb.zip')

      assert_not result[:valid],
                 'Expected zip with extreme compression ratio to be rejected'
      assert_match(/ratio/i, result[:msg])
    end
  ensure
    Doubtfire::Application.config.max_file_size = original_max
    Doubtfire::Application.config.zip_compression_ratio_limit = original_ratio
  end

  test 'zip entry count limit is enforced' do
    original_limit = Doubtfire::Application.config.zip_entry_limit
    Doubtfire::Application.config.zip_entry_limit = 3

    Tempfile.create(['manyfiles', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        5.times { |i| zip.get_output_stream("file_#{i}.txt") { |io| io.write('x') } }
      end

      result = FileHelper.validate_zip_upload(zip_file.path, 'manyfiles.zip')

      assert_not result[:valid],
                 'Expected zip with too many entries to be rejected'
      assert_match(/too many files/i, result[:msg])
    end
  ensure
    Doubtfire::Application.config.zip_entry_limit = original_limit
  end

  test 'total uncompressed size limit is enforced across multiple files in zip' do
    original_max        = Doubtfire::Application.config.max_file_size
    original_multiplier = Doubtfire::Application.config.zip_uncompressed_size_multiplier
    Doubtfire::Application.config.max_file_size = 1_000
    Doubtfire::Application.config.zip_uncompressed_size_multiplier = 2

    Tempfile.create(['bigzip', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        3.times { |i| zip.get_output_stream("part_#{i}.txt") { |io| io.write('a' * 900) } }
      end

      result = FileHelper.validate_zip_upload(zip_file.path, 'bigzip.zip')

      assert_not result[:valid],
                 'Expected rejection when combined uncompressed zip size exceeds limit'
      assert_match(/uncompressed size limit/i, result[:msg])
    end
  ensure
    Doubtfire::Application.config.max_file_size = original_max
    Doubtfire::Application.config.zip_uncompressed_size_multiplier = original_multiplier
  end

  test 'sequential duplicate upload is blocked while first submission is queued' do
    # This deliberately exercises a later request, not a simultaneous race. The
    # first request leaves its payload in :new; the second must be rejected
    # without changing state, storing another payload, or enqueuing another job.
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)
    task    = project.task_for_task_definition(td)

    add_auth_header_for(user: project.student)

    jobs_before = AcceptSubmissionJob.jobs.size
    data = with_file('test_files/submissions/normal.py', 'text/plain',
                     { trigger: 'ready_for_feedback' })
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data
    assert_equal 201, last_response.status,
                 "First upload should succeed (got: #{last_response.body})"
    assert_equal jobs_before + 1, AcceptSubmissionJob.jobs.size,
                 'First upload must enqueue exactly one processing job'
    assert_equal :ready_for_feedback, task.reload.status,
                 'First upload must perform the requested state transition'

    queued_dir = FileHelper.student_work_dir(:new, task, false)
    payloads_after_first = Dir.glob(File.join(queued_dir, '*')).select { |path| File.file?(path) }
    assert_equal 1, payloads_after_first.size,
                 'First upload must leave exactly one payload queued for processing'

    first_submission_count = TaskSubmission.where(task: task).count
    first_submission_date = task.submission_date
    jobs_after_first = AcceptSubmissionJob.jobs.size

    data2 = with_file('test_files/submissions/normal.py', 'text/plain',
                      { trigger: 'need_help' })
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data2

    assert_equal 403, last_response.status,
                 'Second upload while processing should be blocked with 403'
    assert_match(/already being processed/i, last_response.body,
                 'Response should explain the submission is already being processed')
    assert_equal jobs_after_first, AcceptSubmissionJob.jobs.size,
                 'Rejected duplicate must not enqueue another processing job'
    assert_equal payloads_after_first, Dir.glob(File.join(queued_dir, '*')).select { |path| File.file?(path) },
                 'Rejected duplicate must not add or replace queued payloads'
    assert_equal first_submission_count, TaskSubmission.where(task: task).count,
                 'Rejected duplicate must not add a submission row'
    assert_equal :ready_for_feedback, task.reload.status,
                 'Rejected duplicate must not change the accepted submission state'
    assert_equal first_submission_date, task.submission_date,
                 'Rejected duplicate must not change the accepted submission timestamp'
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 10. Cleanup before staging for rejected uploads
  #     Early validation failures must not create task-owned staging paths.
  #     Post-staging failure and abandoned-worker cleanup remain open findings.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'early MIME rejection creates no task-owned staging artifacts' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)
    task    = project.task_for_task_definition(td)

    add_auth_header_for(user: project.student)

    owned_staging_paths = [
      File.join(Dir.tmpdir, 'doubtfire', 'new', task.id.to_s),
      FileHelper.student_work_dir(:new, task, false),
      FileHelper.student_work_dir(:in_process, task, false)
    ]
    assert owned_staging_paths.none? { |path| File.exist?(path) },
           'Fresh task must not already have submission staging paths'

    jobs_before = AcceptSubmissionJob.jobs.size
    submissions_before = TaskSubmission.where(task: task).count
    status_before = task.status

    elf_magic = "\x7fELF\x02\x01\x01\x00#{"\x00" * 8}"
    with_tempfile('.txt', elf_magic, binary: true) do |f|
      post_submission(project, td, Rack::Test::UploadedFile.new(f.path, 'text/plain', true))
    end

    # Assert the upload reached file validation and was rejected for its MIME,
    # rather than passing on an unrelated authentication or processing error.
    assert_equal 403, last_response.status,
                 "Expected MIME validation to reject the upload, got: #{last_response.body}"
    assert_match(/invalid file MIME type/i, last_response.body)
    assert owned_staging_paths.none? { |path| File.exist?(path) },
           'Early rejection must not create task-owned staging files or directories'
    assert_equal jobs_before, AcceptSubmissionJob.jobs.size,
                 'Early rejection must not enqueue submission processing'
    assert_equal submissions_before, TaskSubmission.where(task: task).count,
                 'Early rejection must not create a submission row'
    assert_equal status_before, task.reload.status,
                 'Early rejection must not transition task state'
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 11. Logs must not contain file content, sensitive names, or unnecessary
  #     student information
  # ─────────────────────────────────────────────────────────────────────────────

  test 'rejected submission logs a safe marker without content or student identifiers' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    student = project.student
    td      = create_task_definition(unit: unit)
    project.task_for_task_definition(td)

    add_auth_header_for(user: student)

    sensitive_content = 'SENSITIVE_STUDENT_DATA_12345'
    unsafe_filename = "rejected-#{student.username}-#{student.email}.txt"
    elf_magic = "\x7fELF\x02\x01\x01\x00#{"\x00" * 8}"

    logged = capture_rails_logs do
      with_tempfile('.txt', elf_magic + sensitive_content, binary: true) do |f|
        uploaded = Rack::Test::UploadedFile.new(
          f.path,
          'text/plain',
          true,
          original_filename: unsafe_filename
        )
        post_submission(project, td, uploaded)
      end
    end

    assert_equal 403, last_response.status,
                 'Rejected submission must reach and fail MIME validation'
    assert_match(/invalid file MIME type/i, last_response.body)
    assert_includes logged, 'File MIME check failed',
                    'Expected safe validation marker proving the rejection path logged'
    assert_not_includes logged, sensitive_content,
                        'Rejected submission log must not include file content'
    assert_not_includes logged, student.email,
                        'Rejected submission log must not include student email'
    assert_not_includes logged, student.username,
                        'Rejected submission log must not include student username'
    assert_not_includes logged, unsafe_filename,
                        'Rejected submission log must not include the client filename'
  ensure
    unit.destroy
  end

  test 'accepted submission logs safe markers without content or student identifiers' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    student = project.student
    td      = create_task_definition(unit: unit)
    project.task_for_task_definition(td)

    add_auth_header_for(user: student)

    sensitive_content = "print('SENSITIVE_STUDENT_CODE_67890')"
    unsafe_filename = "accepted-#{student.username}-#{student.email}.py"

    logged = capture_rails_logs do
      with_tempfile('.py', sensitive_content) do |f|
        uploaded = Rack::Test::UploadedFile.new(
          f.path,
          'text/plain',
          true,
          original_filename: unsafe_filename
        )
        post_submission(project, td, uploaded)
      end
    end

    assert_equal 201, last_response.status,
                 'Accepted submission logging test must exercise the successful path'
    assert_includes logged, 'Uploaded file is accepted',
                    'Expected safe file-validation success marker'
    assert_includes logged, 'Submission accepted! Status for task',
                    'Expected safe submission success marker'
    assert_not_includes logged, sensitive_content,
                        'Accepted submission log must not include file content'
    assert_not_includes logged, student.email,
                        'Accepted submission log must not include student email'
    assert_not_includes logged, student.username,
                        'Accepted submission log must not include student username'
    assert_not_includes logged, unsafe_filename,
                        'Accepted submission log must not include the client filename'
  ensure
    unit.destroy
  end

  test 'comment attachment logs a safe marker without content or student identifiers' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    student = project.student
    td      = create_task_definition(unit: unit)
    task    = project.task_for_task_definition(td)

    add_auth_header_for(user: student)

    sensitive_comment = 'SENSITIVE_COMMENT_BODY_24680'
    unsafe_filename = "comment-#{student.username}-#{student.email}.pdf"
    pdf_path = Rails.root.join('test_files/submissions/00_question.pdf')

    logged = capture_rails_logs do
      post "/api/projects/#{project.id}/task_def_id/#{td.id}/comments",
           comment: sensitive_comment,
           attachment: Rack::Test::UploadedFile.new(
             pdf_path,
             'application/pdf',
             true,
             original_filename: unsafe_filename
           )
    end

    assert_equal 201, last_response.status,
                 'Comment logging test must exercise a successful attachment upload'
    assert_includes logged, "user_id=#{student.id} added comment for task #{task.id}",
                    'Expected safe comment audit marker using an internal user id'
    assert_includes logged, 'Uploaded file is accepted',
                    'Expected safe attachment-validation success marker'
    assert_not_includes logged, sensitive_comment,
                        'Comment attachment log must not include comment content'
    assert_not_includes logged, student.email,
                        'Comment attachment log must not include student email'
    assert_not_includes logged, student.username,
                        'Comment attachment log must not include student username'
    assert_not_includes logged, unsafe_filename,
                        'Comment attachment log must not include the client filename'
  ensure
    unit.destroy
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # 13. Attachment retention and deletion behaviour
  #     Deleting a comment must remove its attachment file from disk.
  #     Deleting a task must remove its submission files from disk.
  # ─────────────────────────────────────────────────────────────────────────────

  test 'deleting a comment with an attachment removes the file from disk' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)
    task    = project.task_for_task_definition(td)
    student = project.student

    add_auth_header_for(user: student)

    # Post a comment with a PDF attachment via the API.
    pdf_path = Rails.root.join('test_files/submissions/00_question.pdf')
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/comments",
         comment: 'test attachment',
         attachment: Rack::Test::UploadedFile.new(pdf_path, 'application/pdf', true)

    assert_equal 201, last_response.status, last_response.body

    comment         = task.comments.last
    attachment_path = comment.attachment_path

    assert File.exist?(attachment_path),
           'Attachment file should exist on disk after upload'

    comment.destroy

    assert_not File.exist?(attachment_path),
               'Attachment file must be removed from disk when the comment is deleted'
  ensure
    unit.destroy
  end

  test 'deleting a task comment via API removes the attachment from disk' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)
    task    = project.task_for_task_definition(td)
    student = project.student

    add_auth_header_for(user: student)

    pdf_path = Rails.root.join('test_files/submissions/00_question.pdf')
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/comments",
         comment: 'test attachment',
         attachment: Rack::Test::UploadedFile.new(pdf_path, 'application/pdf', true)

    assert_equal 201, last_response.status, last_response.body

    comment         = task.comments.last
    attachment_path = comment.attachment_path

    assert File.exist?(attachment_path), 'Attachment must exist before deletion'

    delete "/api/projects/#{project.id}/task_def_id/#{td.id}/comments/#{comment.id}"

    assert_includes [200, 204], last_response.status,
                    'Expected 200 or 204 on comment deletion'
    assert_not File.exist?(attachment_path),
               'Attachment file must be removed from disk after API comment deletion'
  ensure
    unit.destroy
  end

  test 'comment attachment returns 404 after comment is deleted' do
    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first
    td      = create_task_definition(unit: unit)
    task    = project.task_for_task_definition(td)
    student = project.student

    add_auth_header_for(user: student)

    pdf_path = Rails.root.join('test_files/submissions/00_question.pdf')
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/comments",
         comment: 'test attachment',
         attachment: Rack::Test::UploadedFile.new(pdf_path, 'application/pdf', true)

    assert_equal 201, last_response.status, last_response.body

    comment    = task.comments.last
    comment_id = comment.id
    comment.destroy

    get "/api/projects/#{project.id}/task_def_id/#{td.id}/comments/#{comment_id}"

    assert_equal 404, last_response.status,
                 'Fetching a deleted comment attachment must return 404'
  ensure
    unit.destroy
  end

end
