# frozen_string_literal: true

require 'test_helper'

class DiscussionCommentApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::TestFileHelper

  def app
    Rails.application
  end

  setup do
    @project = FactoryBot.create(:project)
    @unit = @project.unit
    @task_definition = @unit.task_definitions.first
    @task = @project.task_for_task_definition(@task_definition)
    @student = @project.student
    @tutor = FactoryBot.create(:user, :tutor)
    @unit.employ_staff(@tutor, Role.tutor)
  end

  def test_create_discussion_comment_rejects_empty_attachment_with_bad_request
    add_auth_header_for(user: @tutor)
    comment_count = DiscussionComment.count

    post discussion_comments_endpoint, {
      attachments: [upload_file('test_files/submissions/boo.png', 'audio/wav')]
    }

    assert_equal 400, last_response.status, last_response_body
    assert_equal 'Attachment is empty.', last_response_body['error']
    assert_equal comment_count, DiscussionComment.count
  end

  def test_create_discussion_comment_rejects_oversized_attachment_with_payload_too_large
    add_auth_header_for(user: @tutor)
    comment_count = DiscussionComment.count
    attachment = upload_file('test_files/submissions/00_question.pdf', 'audio/wav')

    File.stub :size?, 30_000_001 do
      post discussion_comments_endpoint, { attachments: [attachment] }
    end

    assert_equal 413, last_response.status, last_response_body
    assert_equal 'Attachment exceeds the maximum attachment size of 30MB.', last_response_body['error']
    assert_equal comment_count, DiscussionComment.count
  end

  def test_discussion_reply_rejects_empty_attachment_with_bad_request
    discussion = create_discussion_comment
    add_auth_header_for(user: @student)

    post discussion_reply_endpoint(discussion), {
      attachment: upload_file('test_files/submissions/boo.png', 'audio/wav')
    }

    assert_equal 400, last_response.status, last_response_body
    assert_equal 'Attachment is empty.', last_response_body['error']
    assert_nil discussion.reload.time_discussion_completed
  end

  def test_discussion_reply_rejects_oversized_attachment_with_payload_too_large
    discussion = create_discussion_comment
    add_auth_header_for(user: @student)
    attachment = upload_file('test_files/submissions/00_question.pdf', 'audio/wav')

    File.stub :size?, 30_000_001 do
      post discussion_reply_endpoint(discussion), { attachment: attachment }
    end

    assert_equal 413, last_response.status, last_response_body
    assert_equal 'Attachment exceeds the maximum attachment size of 30MB.', last_response_body['error']
    assert_nil discussion.reload.time_discussion_completed
  end

  private

  def discussion_comments_endpoint
    "/api/projects/#{@project.id}/task_def_id/#{@task_definition.id}/discussion_comments"
  end

  def discussion_reply_endpoint(discussion)
    "/api/projects/#{@project.id}/task_def_id/#{@task_definition.id}/comments/#{discussion.id}/discussion_comment/reply"
  end

  def create_discussion_comment
    DiscussionComment.create!(
      task: @task,
      user: @tutor,
      recipient: @student,
      content_type: 'discussion',
      number_of_prompts: 1
    )
  end
end
