require "test_helper"
require "open3"
require "zip"

class FileHelperTest < ActiveSupport::TestCase
  def capture_upload_logs
    output = StringIO.new
    test_logger = Logger.new(output)
    test_logger.level = Logger::INFO
    FileHelper.stub(:logger, test_logger) { yield }
    output.string
  end

  def test_extension_rejection_is_visible_at_info_without_filename_or_temp_path
    Tempfile.create(['private-student-name', '.txt']) do |file|
      file.write('private file content')
      file.flush
      logs = capture_upload_logs do
        result = FileHelper.accept_file(
          {'filename' => "private-student-email@example.invalid.exe", 'tempfile' => file},
          'private requirement label', 'comment_attachment'
        )
        refute result[:accepted]
      end
      assert_includes logs, 'File extension check failed'
      assert_includes logs, '"kind":"comment_attachment"'
      assert_includes logs, '"uploaded_extension":".exe"'
      assert_includes logs, '"temporary_extension":".txt"'
      refute_includes logs, 'private'
      refute_includes logs, file.path
    end
  end

  def test_unknown_upload_kind_fails_closed_without_logging_caller_controlled_values
    Tempfile.create(['private-student-name', '.txt']) do |file|
      file.write('private file content')
      file.flush

      logs = capture_upload_logs do
        result = FileHelper.accept_file(
          { 'filename' => 'private-student-name.txt', 'tempfile' => file },
          'private requirement label',
          "private-kind\nforged-log-entry"
        )

        assert_not result[:accepted]
        assert_equal 'unsupported file type.', result[:msg]
      end

      assert_includes logs, 'Unknown file type'
      assert_includes logs, '"kind":"unknown"'
      assert_not_includes logs, 'private'
      assert_not_includes logs, 'forged-log-entry'
      assert_not_includes logs, file.path
    end
  end

  def test_mime_rejection_is_visible_at_info_with_detected_type_and_policy
    Tempfile.create(['private-report', '.pdf']) do |file|
      file.write('private plain text pretending to be a PDF')
      file.flush
      logs = capture_upload_logs do
        result = FileHelper.accept_file(
          {filename: 'private-report.pdf', 'tempfile' => file}, 'PDF', 'document'
        )
        refute result[:accepted]
      end
      assert_includes logs, 'File MIME check failed'
      assert_includes logs, '"detected_mime":"text/plain'
      assert_includes logs, '"allowed_mime":["application/pdf"]'
      refute_includes logs, 'private'
      refute_includes logs, file.path
    end
  end

  def test_structural_rejection_is_visible_but_success_stays_at_debug
    Tempfile.create(['private-submission', '.zip']) do |file|
      Zip::File.open(file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('../private-escape.txt') { |io| io.write('private content') }
      end
      logs = capture_upload_logs do
        result = FileHelper.accept_file({filename: 'archive.zip', 'tempfile' => file}, 'Zip', 'zip')
        refute result[:accepted]
      end
      assert_includes logs, 'Zip file is invalid'
      refute_includes logs, 'private'
      refute_includes logs, file.path
    end
    Tempfile.create(['valid', '.py']) do |file|
      file.write("print('hello')\n")
      file.flush
      logs = capture_upload_logs do
        result = FileHelper.accept_file({filename: 'valid.py', 'tempfile' => file}, 'Code', 'code')
        assert result[:accepted], result[:msg]
      end
      assert_empty logs
    end
  end

  def test_convert_use_with_gif
    in_file = "#{Rails.root}/test_files/submissions/unbelievable.gif"

    Dir.mktmpdir do |dir|
      dest_file = "#{dir}#{File.basename(in_file, ".*")}.jpg"
      assert FileHelper.compress_image_to_dest(in_file, dest_file, true)
      assert File.exist? dest_file
    end
  end

  def test_archive_paths
    unit = FactoryBot.create(:unit, with_students: false)

    archive_work_path = FileHelper.unit_work_root(unit, archived: :force)
    original_work_path = FileHelper.unit_work_root(unit, archived: false)

    archive_portfolio_path = FileHelper.unit_portfolio_dir(unit, create: false, archived: :force)
    original_portfolio_path = FileHelper.unit_portfolio_dir(unit, create: false, archived: false)

    archive_jplag_path = FileHelper.unit_jplag_report_dir(unit, archived: :force)
    original_jplag_path = FileHelper.unit_jplag_report_dir(unit, archived: false)

    assert_match %r{^#{FileHelper.archive_root}/}, archive_work_path
    assert_match %r{^#{FileHelper.archive_root}/portfolio/}, archive_portfolio_path
    assert_match %r{^#{FileHelper.archive_root}/jplag/results/}, archive_jplag_path
    assert_match %r{^#{FileHelper.student_work_root}/}, original_work_path
    assert_match %r{^#{FileHelper.student_work_root}/portfolio/}, original_portfolio_path
    assert_match %r{^#{FileHelper.student_work_root}/jplag/results/}, original_jplag_path
  end

  def test_accept_zip_upload
    Tempfile.create(['submission', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('src/main.rb') { |io| io.write("puts 'hello'\n") }
      end

      result = FileHelper.accept_file(
        {
          filename: 'submission.zip',
          'tempfile' => zip_file
        },
        'Zip',
        'zip'
      )

      assert result[:accepted], result[:msg]
    end
  end

  def test_zip_upload_rejects_unsafe_paths
    Tempfile.create(['submission', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('../escape.rb') { |io| io.write("puts 'bad'\n") }
      end

      result = FileHelper.accept_file(
        {
          filename: 'submission.zip',
          'tempfile' => zip_file
        },
        'Zip',
        'zip'
      )

      refute result[:accepted]
      assert_includes result[:msg], 'unsafe path'
    end
  end

  def test_zip_upload_rejects_nested_archives
    Tempfile.create(['submission', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('lib/vendor.zip') { |io| io.write('nested archive') }
      end

      result = FileHelper.accept_file(
        {
          filename: 'submission.zip',
          'tempfile' => zip_file
        },
        'Zip',
        'zip'
      )

      refute result[:accepted]
      assert_includes result[:msg], 'Nested archives are not allowed'
    end
  end

  def test_zip_upload_accepts_entries_larger_than_file_limit
    original_max_file_size = Doubtfire::Application.config.max_file_size
    Doubtfire::Application.config.max_file_size = 1_000

    Tempfile.create(['submission', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('large.txt') { |io| io.write('a' * 1_001) }
      end

      result = FileHelper.accept_file(
        {
          filename: 'submission.zip',
          'tempfile' => zip_file
        },
        'Zip',
        'zip'
      )

      assert result[:accepted], result[:msg]
    end
  ensure
    Doubtfire::Application.config.max_file_size = original_max_file_size
  end

  def test_zip_upload_rejects_total_uncompressed_size_over_multiplier_limit
    original_max_file_size = Doubtfire::Application.config.max_file_size
    original_multiplier = Doubtfire::Application.config.zip_uncompressed_size_multiplier
    Doubtfire::Application.config.max_file_size = 1_000
    Doubtfire::Application.config.zip_uncompressed_size_multiplier = 2

    Tempfile.create(['submission', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        3.times do |index|
          zip.get_output_stream("file-#{index}.txt") { |io| io.write('a' * 900) }
        end
      end

      result = FileHelper.validate_zip_upload(zip_file.path, 'submission.zip')

      refute result[:valid]
      assert_includes result[:msg], 'uncompressed size limit'
    end
  ensure
    Doubtfire::Application.config.max_file_size = original_max_file_size
    Doubtfire::Application.config.zip_uncompressed_size_multiplier = original_multiplier
  end

  def test_zip_file_tree_lists_nested_paths
    Tempfile.create(['submission', '.zip']) do |zip_file|
      Zip::File.open(zip_file.path, Zip::File::CREATE) do |zip|
        zip.get_output_stream('src/main.rb') { |io| io.write("puts 'hello'\n") }
        zip.get_output_stream('README.md') { |io| io.write("# Read me\n") }
      end

      tree = FileHelper.zip_file_tree(zip_file.path, 'submission.zip')

      assert_equal 2, tree[:entries]
      assert_includes tree[:lines], '↳ src/'
      assert_includes tree[:lines], '  ↳ main.rb'
      assert_includes tree[:lines], '↳ README.md'
      refute tree[:truncated]
    end
  end

  def test_process_audio_converts_webm_audio
    Dir.mktmpdir("audio path ") do |dir|
      source_wav = File.join(dir, "source tone.wav")
      webm_input = File.join(dir, "browser recording.webm")
      wav_output = File.join(dir, "processed recording.wav")

      source_success = system(
        Doubtfire::Application.config.institution[:ffmpeg],
        "-loglevel", "quiet",
        "-y",
        "-f", "lavfi",
        "-i", "sine=frequency=440:duration=1",
        source_wav
      )
      assert source_success, "Expected ffmpeg to create a WAV fixture for the test"

      success = system(
        Doubtfire::Application.config.institution[:ffmpeg],
        "-loglevel", "quiet",
        "-y",
        "-i", source_wav,
        "-c:a", "libopus",
        webm_input
      )
      assert success, "Expected ffmpeg to create a WebM fixture for the test"

      assert FileHelper.process_audio(webm_input, wav_output)
      assert File.exist?(wav_output)
      assert_operator File.size(wav_output), :>, 0
    end
  end
end
