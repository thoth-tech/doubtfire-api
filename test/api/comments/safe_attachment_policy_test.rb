# frozen_string_literal: true

require 'test_helper'

class SafeAttachmentPolicyTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  setup do
    @project = FactoryBot.create(:project)
    @task_definition = @project.unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @endpoint = "/api/projects/#{@project.id}/task_def_id/#{@task_definition.id}/comments"
    add_auth_header_for(user: @project.student)
  end

  def with_csv(content = "name,score\nExample,7\n", filename: 'results.csv')
    Tempfile.create(['safe-attachment', '.csv']) do |file|
      file.write(content)
      file.flush
      yield Rack::Test::UploadedFile.new(file.path, 'text/csv', true, original_filename: filename)
    end
  end

  test 'authenticated policy is explicit and keeps legacy XLS out of chat' do
    get '/api/task_comments/upload_policy'
    assert_equal 200, last_response.status
    assert_equal 30_000_000, last_response_body['max_bytes_exclusive']
    spreadsheet = last_response_body['categories'].find { |item| item['id'] == 'spreadsheet' }
    assert_equal %w[csv xlsx], spreadsheet['extensions']
    assert_equal 'download', spreadsheet['preview']
    assert_not_includes last_response.body, 'mime_types'
  end

  test 'CSV is stored unchanged and downloaded with safe metadata and headers' do
    with_csv do |file|
      post @endpoint, attachment: file
    end
    assert_equal 201, last_response.status, last_response.body
    comment = TaskComment.find(last_response_body['id'])
    assert_equal 'spreadsheet', last_response_body['type']
    assert_equal 'results.csv', last_response_body['attachment_file_name']
    assert_equal "name,score\nExample,7\n", File.read(comment.attachment_path)
    get "#{@endpoint}/#{comment.id}?as_attachment=false"
    assert_equal 200, last_response.status
    assert_match(/attachment/, last_response.headers['Content-Disposition'])
    assert_equal 'nosniff', last_response.headers['X-Content-Type-Options']
    assert_equal 'no-cache', last_response.headers['Cache-Control']
  ensure
    comment&.destroy
  end

  test 'malformed and spoofed CSV or legacy XLS are rejected without stored rows' do
    initial = @task.comments.count
    [["\"unterminated", 'bad.csv'], ["MZ\x00binary", 'bad.csv'], ['a,b', 'macro.xls'], ['a,b', 'active.xlsm'], ['a,b', 'fake.xlsx']].each do |content, filename|
      with_csv(content, filename: filename) { |file| post @endpoint, attachment: file }
      assert_equal 403, last_response.status, last_response.body
      assert_match(/\AUPLOAD_/, last_response_body['code'])
      assert_equal initial, @task.comments.count
    end
  end

  test 'empty and exact boundary have stable failure codes' do
    with_csv('') { |file| post @endpoint, attachment: file }
    assert_equal 400, last_response.status
    assert_equal 'UPLOAD_EMPTY', last_response_body['code']
    with_csv('x' * 30_000_000) { |file| post @endpoint, attachment: file }
    assert_equal 413, last_response.status
    assert_equal 'UPLOAD_TOO_LARGE', last_response_body['code']
  end

  test 'other project student cannot retrieve spreadsheet through either project route' do
    with_csv { |file| post @endpoint, attachment: file }
    assert_equal 201, last_response.status
    comment = TaskComment.find(last_response_body['id'])
    other = FactoryBot.create(:project)
    add_auth_header_for(user: other.student)
    get "#{@endpoint}/#{comment.id}"
    assert_equal 403, last_response.status
    get "/api/projects/#{other.id}/task_def_id/#{other.unit.task_definitions.first.id}/comments/#{comment.id}"
    assert_equal 404, last_response.status
  ensure
    comment&.destroy
  end
  test 'a rejected upload logs a safe reason without claiming a comment was added' do
    output = StringIO.new
    log = ActiveSupport::Logger.new(output)
    log.level = Logger::INFO
    original = Rails.logger
    Rails.logger = log
    with_csv('private file content', filename: 'private-student-name.exe') do |file|
      post @endpoint, attachment: file
    end
    assert_equal 403, last_response.status
    assert_includes output.string, 'File extension check failed'
    assert_not_includes output.string, 'added comment'
    assert_not_includes output.string, 'private-student-name'
    assert_not_includes output.string, 'private file content'
  ensure
    Rails.logger = original
  end

  test 'task Spreadsheet requirement accepts CSV through the submission API and retains the original' do
    @task_definition.update!(
      start_date: Time.zone.now - 1.week,
      target_date: Time.zone.now + 1.week,
      upload_requirements: [{ 'key' => 'file0', 'name' => 'Results', 'type' => 'csv' }]
    )
    with_csv do |file|
      post "/api/projects/#{@project.id}/task_def_id/#{@task_definition.id}/submission",
           trigger: 'ready_for_feedback', file0: file
    end
    assert_equal 201, last_response.status, last_response.body
    @task.reload
    stored = File.join(@task.student_work_dir(:new, false), '000-csv.csv')
    assert File.exist?(stored)
    assert_equal "name,score\nExample,7\n", File.read(stored)
    assert(AcceptSubmissionJob.jobs.any? { |job| job['args'].first == @task.id })
  ensure
    FileUtils.rm_rf(@task.student_work_dir(:new, false)) if @task
  end

  test 'staff document and spreadsheet comments count as manual feedback but student attachments do not' do
    tutor = @project.unit.staff.first.user
    %w[document spreadsheet].each do |type|
      comment = TaskComment.create!(task: @task, user: tutor, recipient: @project.student,
                                    content_type: type, comment: 'Attached feedback')
      assert @task.has_manual_feedback_since_first_ready_for_feedback?
      assert @task.has_recent_manual_feedback_from_tutor?(tutor)
      comment.update!(user: @project.student)
      assert_not @task.has_manual_feedback_since_first_ready_for_feedback?
      assert_not @task.has_recent_manual_feedback_from_tutor?(tutor)
      comment.destroy!
    end
  end

end
