# frozen_string_literal: true

require 'test_helper'

class Batch03DocxAttachmentTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  DOCX_MIME_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'

  def app
    Rails.application
  end

  def setup
    super
    @project = FactoryBot.create(:project)
    @student = @project.student
    @task_definition = @project.unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @comments_endpoint = "/api/projects/#{@project.id}/task_def_id/#{@task_definition.id}/comments"
    @docx_path = Rails.root.join('test_files/TestWordDoc.docx')
    add_auth_header_for(user: @student)
  end

  def docx_upload(filename: 'Phone evidence.docx')
    Rack::Test::UploadedFile.new(
      @docx_path,
      DOCX_MIME_TYPE,
      true,
      original_filename: filename
    )
  end

  test 'uploads and downloads DOCX with exact bytes and attachment metadata' do
    original_bytes = File.binread(@docx_path)
    original_filename = 'Phone evidence original.docx'

    post @comments_endpoint,
         comment: 'Evidence captured on phone',
         attachment: docx_upload(filename: original_filename),
         client_request_id: SecureRandom.uuid

    assert_equal 201, last_response.status, last_response.body
    response = last_response_body
    comment = TaskComment.find(response.fetch('id'))

    assert_equal 'document', comment.content_type
    assert_equal '.docx', comment.attachment_extension
    assert_equal original_filename, comment.attachment_file_name
    assert_equal DOCX_MIME_TYPE, comment.attachment_mime_type
    assert_equal original_bytes.bytesize, comment.attachment_size
    assert_equal original_bytes, File.binread(comment.attachment_path)

    assert_equal true, response['has_attachment']
    assert_equal 'document', response['type']
    assert_equal original_filename, response['attachment_file_name']
    assert_equal DOCX_MIME_TYPE, response['attachment_mime_type']
    assert_equal original_bytes.bytesize, response['attachment_byte_size']

    get "#{@comments_endpoint}/#{comment.id}"

    assert_equal 200, last_response.status, last_response.body
    assert_equal original_bytes, last_response.body
    assert_match(/\A#{Regexp.escape(DOCX_MIME_TYPE)}(?:;|\z)/, last_response.headers['Content-Type'].to_s)
    assert_match(/attachment/i, last_response.headers['Content-Disposition'].to_s)
    assert_includes last_response.headers['Content-Disposition'].to_s, original_filename
  ensure
    comment&.destroy
  end

  test 'repeating a client request id returns the same comment and creates one row' do
    client_request_id = SecureRandom.uuid
    initial_count = @task.comments.where(user_id: @student.id, client_request_id: client_request_id).count

    post @comments_endpoint,
         attachment: docx_upload,
         client_request_id: client_request_id

    assert_equal 201, last_response.status, last_response.body
    first_response = last_response_body

    post @comments_endpoint,
         attachment: docx_upload(filename: 'Retry should not replace original.docx'),
         client_request_id: client_request_id

    assert_equal 201, last_response.status, last_response.body
    second_response = last_response_body

    assert_equal first_response['id'], second_response['id']
    assert_equal initial_count + 1,
                 @task.comments.where(user_id: @student.id, client_request_id: client_request_id).count
    assert_equal 'Phone evidence.docx', TaskComment.find(first_response['id']).attachment_file_name
  ensure
    TaskComment.where(task: @task, user: @student, client_request_id: client_request_id).destroy_all if client_request_id
  end

  test 'repeating a text client request id returns the same comment and creates one row' do
    client_request_id = SecureRandom.uuid
    initial_count = @task.comments.where(user_id: @student.id, client_request_id: client_request_id).count

    post_json @comments_endpoint,
              comment: 'Typed once while uploading several attachments',
              client_request_id: client_request_id

    assert_equal 201, last_response.status, last_response.body
    first_response = last_response_body

    post_json @comments_endpoint,
              comment: 'Typed once while uploading several attachments',
              client_request_id: client_request_id

    assert_equal 201, last_response.status, last_response.body
    second_response = last_response_body

    assert_equal first_response['id'], second_response['id']
    assert_equal initial_count + 1,
                 @task.comments.where(user_id: @student.id, client_request_id: client_request_id).count
  ensure
    TaskComment.where(task: @task, user: @student, client_request_id: client_request_id).destroy_all if client_request_id
  end

  test 'serves a stored Unicode HTML-like filename with RFC 5987 download disposition' do
    supplied_filename = 'evidence <draft>.DOCX'
    stored_filename = '📱 evidence <draft>.DOCX'

    post @comments_endpoint,
         attachment: docx_upload(filename: supplied_filename),
         client_request_id: SecureRandom.uuid

    assert_equal 201, last_response.status, last_response.body
    comment = TaskComment.find(last_response_body.fetch('id'))
    assert_equal supplied_filename, comment.attachment_file_name
    comment.update!(attachment_original_filename: stored_filename)
    comment.reload

    assert_equal stored_filename, comment.attachment_file_name
    assert_operator comment.attachment_file_name.length, :<=, 255
    assert_equal comment.attachment_file_name.gsub(/[[:cntrl:]]/, ''), comment.attachment_file_name
    assert_not_includes comment.attachment_file_name, '/'

    get "#{@comments_endpoint}/#{comment.id}"

    assert_equal 200, last_response.status, last_response.body
    disposition = last_response.headers['Content-Disposition'].to_s
    assert_match(/\Aattachment;/i, disposition)
    assert_match(/filename\*=UTF-8''/i, disposition)
    assert_match(/%F0%9F%93%B1/i, disposition)
    assert_no_match(/[\r\n]/, disposition)
  ensure
    comment&.destroy
  end

  test 'rejects an attachment exactly at the 30MB boundary without creating a comment' do
    initial_count = @task.comments.count

    Tempfile.create(['batch03-size-boundary', '.docx']) do |tempfile|
      tempfile.truncate(30_000_000)
      tempfile.flush

      post @comments_endpoint,
           attachment: Rack::Test::UploadedFile.new(
             tempfile.path,
             DOCX_MIME_TYPE,
             true,
             original_filename: 'at-limit.docx'
           ),
           client_request_id: SecureRandom.uuid
    end

    assert_includes 400..499, last_response.status, last_response.body
    assert_match(/maximum attachment size of 30MB/i, last_response_body.fetch('error'))
    assert_equal initial_count, @task.comments.count
  end

  test 'a different student cannot download the DOCX attachment' do
    unit = FactoryBot.create(:unit, student_count: 2)
    owner_project, other_project = unit.active_projects.first(2)
    task_definition = unit.task_definitions.first
    endpoint = "/api/projects/#{owner_project.id}/task_def_id/#{task_definition.id}/comments"

    add_auth_header_for(user: owner_project.student)
    post endpoint,
         attachment: docx_upload,
         client_request_id: SecureRandom.uuid

    assert_equal 201, last_response.status, last_response.body
    comment = TaskComment.find(last_response_body.fetch('id'))

    add_auth_header_for(user: other_project.student)
    get "#{endpoint}/#{comment.id}"

    assert_equal 403, last_response.status, last_response.body
    assert_match(/cannot read the comments/i, last_response_body.fetch('error'))
  ensure
    comment&.destroy
    unit&.destroy
  end

  test 'a DOCX storage failure leaves no task comment row' do
    initial_count = @task.comments.count
    move_failure = lambda do |_source, _destination|
      raise IOError, 'simulated Batch03 storage failure'
    end

    FileUtils.stub(:mv, move_failure) do
      post @comments_endpoint,
           attachment: docx_upload,
           client_request_id: SecureRandom.uuid
    end

    assert_includes 500..599, last_response.status, last_response.body
    assert_equal initial_count, @task.comments.count
  end

  test 'a failure after the DOCX is stored removes the file before the rollback' do
    initial_count = @task.comments.count
    comment_dir = FileHelper.student_work_dir(:comment, @task)
    files_before = Dir.children(comment_dir).sort
    outer_transactions = TaskComment.connection.open_transactions
    removals = []
    original_rm_f = FileUtils.method(:rm_f)
    recording_rm_f = lambda do |path, **options|
      removals << [path.to_s, TaskComment.connection.open_transactions] if path.to_s.start_with?(comment_dir)
      original_rm_f.call(path, **options)
    end
    # safe_upload_filename runs after the file has been moved into place.
    failure_after_storage = lambda do |*_args, **_options|
      raise IOError, 'simulated failure after storage'
    end

    FileUtils.stub(:rm_f, recording_rm_f) do
      FileHelper.stub(:safe_upload_filename, failure_after_storage) do
        post @comments_endpoint,
             attachment: docx_upload,
             client_request_id: SecureRandom.uuid
      end
    end

    assert_includes 500..599, last_response.status, last_response.body
    assert_equal initial_count, @task.comments.count
    assert_equal files_before, Dir.children(comment_dir).sort

    # Outside tests the rollback is a real one and resets the new row's id,
    # which the storage path is built from, so the file must be removed while
    # the transaction is still open. A test savepoint keeps the id, so the
    # order is asserted directly.
    removal = removals.find { |path, _open_transactions| path.end_with?('.docx') }
    assert removal, 'the stored DOCX should be removed'
    assert_operator removal.last, :>, outer_transactions
  end

  test 'an overlapping attachment retry that loses the race returns the stored comment' do
    client_request_id = SecureRandom.uuid
    original_accept_file = FileHelper.method(:accept_file)
    winner = nil
    # The endpoint's format check runs after its client_request_id lookup, so
    # storing the original request here reproduces a retry that missed it.
    racing_accept_file = lambda do |*args|
      winner ||= @task.add_text_comment(@student, 'Original request', nil, client_request_id)
      original_accept_file.call(*args)
    end

    FileHelper.stub(:accept_file, racing_accept_file) do
      post @comments_endpoint,
           attachment: docx_upload,
           client_request_id: client_request_id
    end

    assert_equal 201, last_response.status, last_response.body
    assert_equal winner.id, last_response_body['id']
    assert_equal 1, @task.comments.where(user_id: @student.id, client_request_id: client_request_id).count
  ensure
    TaskComment.where(task: @task, user: @student, client_request_id: client_request_id).destroy_all if client_request_id
  end

  test 'an overlapping text retry that loses the race returns the stored comment' do
    client_request_id = SecureRandom.uuid
    text = 'Typed once, sent twice'
    parent = @task.add_text_comment(@student, 'Earlier message')
    # The original request's comment, under a placeholder id so the retry's
    # first lookup misses it.
    winner = @task.add_text_comment(@student, text, nil, SecureRandom.uuid)
    original_find = TaskComment.method(:find)
    raced = false
    # Replying makes the endpoint load the parent after its first lookup, and
    # the original request "commits" here. The raw update stands in for that
    # request's own connection: like a commit elsewhere, it does not clear this
    # request's query cache, which still holds the first lookup's miss.
    racing_find = lambda do |*args|
      unless raced
        raced = true
        TaskComment.connection.raw_connection.query(
          "UPDATE task_comments SET client_request_id = '#{client_request_id}' WHERE id = #{winner.id}"
        )
      end
      original_find.call(*args)
    end

    ActiveRecord::Base.cache do
      TaskComment.stub(:find, racing_find) do
        post_json @comments_endpoint,
                  comment: text,
                  reply_to_id: parent.id,
                  client_request_id: client_request_id
      end
    end

    assert_equal 201, last_response.status, last_response.body
    assert_equal winner.id, last_response_body['id']
    assert_equal 1, @task.comments.where(user_id: @student.id, client_request_id: client_request_id).count
  ensure
    TaskComment.where(task: @task, user: @student, client_request_id: client_request_id).destroy_all if client_request_id
    parent&.destroy
  end

  test 'a converted image downloads with the extension of the stored format' do
    post @comments_endpoint,
         attachment: Rack::Test::UploadedFile.new(
           Rails.root.join('test_files/submissions/Deakin_Logo.jpeg'),
           'image/png',
           true,
           original_filename: 'Screenshot 1.png'
         ),
         client_request_id: SecureRandom.uuid

    assert_equal 201, last_response.status, last_response.body
    comment = TaskComment.find(last_response_body.fetch('id'))
    # Images other than GIF are stored as JPEG, so the download name follows.
    assert_equal '.jpg', comment.attachment_extension
    assert_equal 'Screenshot 1.jpg', comment.attachment_file_name
    assert_equal 'Screenshot 1.jpg', last_response_body['attachment_file_name']
  ensure
    comment&.destroy
  end

  test 'a comment that is only a NUL character is not stored' do
    initial_count = @task.comments.count

    post_json @comments_endpoint, comment: "\u0000"

    assert_equal 403, last_response.status, last_response.body
    assert_equal initial_count, @task.comments.count
  end

  test 'a text comment that only differs by surrounding whitespace is still a duplicate' do
    post_json @comments_endpoint, comment: 'Please check the second figure'
    assert_equal 201, last_response.status, last_response.body

    post_json @comments_endpoint, comment: "  Please check the second figure \n"

    assert_equal 403, last_response.status, last_response.body
    assert_equal 1, @task.comments.where(user_id: @student.id, comment: 'Please check the second figure').count
  end

  test 'unsupported attachment returns a controlled 4xx without creating a comment' do
    initial_count = @task.comments.count
    invalid_upload = Rack::Test::UploadedFile.new(
      Rails.root.join('test_files/submissions/test.txt'),
      'text/plain',
      true,
      original_filename: 'unsupported.txt'
    )

    post @comments_endpoint,
         attachment: invalid_upload,
         client_request_id: SecureRandom.uuid

    assert_includes 400..499, last_response.status, last_response.body
    assert_match(/not an acceptable format/i, last_response_body.fetch('error'))
    assert_equal initial_count, @task.comments.count
  end
end
