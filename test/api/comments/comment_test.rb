require 'test_helper'

class CommentTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include ActiveSupport::Testing::TimeHelpers
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::TestFileHelper

  def app
    Rails.application
  end

  def test_get_comments
    project = FactoryBot.create(:project)
    unit = project.unit
    user = project.student
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)

    add_auth_header_for user: user
    get "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments"

    assert_equal 200, last_response.status, last_response_body
    assert_equal 0, last_response_body.length, last_response_body.inspect

    task.add_text_comment(convenor, 'Hello World')
    task.add_text_comment(convenor, 'Message 2')
    task.add_text_comment(convenor, 'Last message')

    get "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments"

    assert_equal 200, last_response.status, last_response_body
    assert_equal 3, last_response_body.length, last_response_body.inspect

    keys = %w(id comment has_attachment type is_new reply_to_id author recipient created_at recipient_read_time)
    keys_test = %w(id comment reply_to_id)

    last_response_body.each do |resp|
      assert_json_limit_keys_to_exactly keys, resp
      comment = TaskComment.find(resp['id'])
      assert_json_matches_model comment, resp, keys_test
      assert resp['is_new'], resp.inspect
    end

    # Test they are now read...
    get "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments"

    assert_equal 200, last_response.status, last_response_body
    assert_equal 3, last_response_body.length, last_response_body.inspect

    keys = %w(id comment has_attachment type is_new reply_to_id author recipient created_at recipient_read_time)
    keys_test = %w(id comment reply_to_id)

    last_response_body.each do |resp|
      assert_json_limit_keys_to_exactly keys, resp
      comment = TaskComment.find(resp['id'])
      assert_json_matches_model comment, resp, keys_test
      refute resp['is_new'], resp.inspect
    end

    task.add_text_comment(user, 'Response')
  end

  def test_student_post_comment
    project = Project.first
    user = project.student
    unit = project.unit
    task_definition = unit.task_definitions.first
    tutor = project.tutor_for(task_definition)

    pre_count = TaskComment.count

    comment_data = { comment: 'Hello World' }

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 201, last_response.status

    assert_equal 'Hello World', TaskComment.last.comment, 'last comment has message'
    assert_equal pre_count + 1, TaskComment.count, 'one comment added'

    expected_response = {
      'comment' => 'Hello World',
      'has_attachment' => false,
      'type' => 'text',
      'is_new' => false,
      author: { 'id' => user.id },
      recipient: { 'id' => tutor.id }
    }

    # check each is the same
    assert_json_matches_model expected_response, last_response_body, %w(comment has_attachment type is_new)
    assert_json_matches_model expected_response[:author], last_response_body['author'], ['id']
    assert_json_matches_model expected_response[:recipient], last_response_body['recipient'], ['id']
  end

  def test_replying_to_comments
    campus = FactoryBot.create(:campus)
    unit = FactoryBot.create(:unit, student_count: 2)
    unit.employ_staff(User.first, Role.convenor)
    project = FactoryBot.create(:project, unit: unit, campus: campus)
    user = project.student
    task_definition = unit.task_definitions.first
    tutor = project.tutor_for(task_definition)

    comment_data = { comment: 'Hello World' }

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    # Post original comment and check that it was successful
    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data
    assert_equal 201, last_response.status

    expected_response = {
      'comment' => 'Responding!',
      'has_attachment' => false,
      'type' => 'text',
      'reply_to_id' => TaskComment.last.id,
      author: { 'id' => user.id },
      recipient: { 'id' => tutor.id }
    }

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    # Student responding to self
    comment_data = { comment: 'Responding!', reply_to_id: TaskComment.last.id }
    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data
    assert_equal 201, last_response.status
    assert_json_matches_model expected_response, last_response_body, %w(comment type reply_to_id)

    expected_response = {
      'comment' => 'Responding again!',
      'has_attachment' => false,
      'type' => 'text',
      'reply_to_id' => TaskComment.last.id,
      author: { 'id' => user.id },
      recipient: { 'id' => tutor.id }
    }

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    # Tutor responding to student
    comment_data = { comment: 'Responding again!', reply_to_id: TaskComment.last.id }
    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data
    assert_equal 201, last_response.status

    # check each is the same
    assert_json_matches_model expected_response, last_response_body, %w(comment type reply_to_id)
  end

  def test_student_post_reply_to_invalid_comment
    campus = FactoryBot.create(:campus)
    unit = FactoryBot.create(:unit, student_count: 2)
    unit.employ_staff(User.first, Role.convenor)
    project = FactoryBot.create(:project, unit: unit, campus: campus)
    user = project.student
    task_definition = unit.task_definitions.first
    tutor = project.tutor_for(task_definition)

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    comment_data = { comment: 'Responding!', reply_to_id: -1 }

    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 404, last_response.status
  end

  def test_student_reply_to_student_in_same_unit
    campus = FactoryBot.create(:campus)
    unit = FactoryBot.create(:unit, student_count: 2)
    project_1 = FactoryBot.create(:project, unit: unit, campus: campus)
    project_2 = FactoryBot.create(:project, unit: unit, campus: campus)
    student_1 = project_1.student
    student_2 = project_2.student

    task_definition = unit.task_definitions.first

    # Add auth_token and username to header
    add_auth_header_for(user: student_1)

    post_json "/api/projects/#{project_1.id}/task_def_id/#{task_definition.id}/comments", comment: 'Hello World'
    assert_equal 201, last_response.status
    id = last_response_body['id']

    # Add auth_token and username to header
    add_auth_header_for(user: student_2)

    post_json "/api/projects/#{project_1.id}/task_def_id/#{task_definition.id}/comments", comment: 'Hello World', reply_to_id: id
    assert_equal 403, last_response.status
  end

  def test_student_reply_to_themselve_in_different_task_same_project
    campus = FactoryBot.create(:campus)
    unit = FactoryBot.create(:unit, student_count: 2)
    project_1 = FactoryBot.create(:project, unit: unit, campus: campus)
    student_1 = project_1.student

    task_definition_1 = unit.task_definitions.first
    task_definition_2 = unit.task_definitions.second

    # Add auth_token and username to header
    add_auth_header_for(user: student_1)

    post_json "/api/projects/#{project_1.id}/task_def_id/#{task_definition_1.id}/comments", comment: 'Hello World'
    assert_equal 201, last_response.status
    id = last_response_body['id']

    # Add auth_token and username to header
    add_auth_header_for(user: student_1)

    post_json "/api/projects/#{project_1.id}/task_def_id/#{task_definition_2.id}/comments", comment: 'Hello World', reply_to_id: id
    assert_equal 404, last_response.status
  end

  def test_student_can_edit_own_comment_within_10_minutes
    project = Project.first
    user = project.student
    task_definition = project.unit.task_definitions.first

    add_auth_header_for(user: user)
    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment: 'Original comment'
    assert_equal 201, last_response.status

    comment_id = last_response_body['id']

    travel_to 9.minutes.from_now do
      put_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments/#{comment_id}", comment: 'Edited comment'
      assert_equal 200, last_response.status, last_response.body
    end

    assert_equal 'Edited comment', TaskComment.find(comment_id).read_attribute(:comment)
    assert_equal 'Edited comment', last_response_body['comment']
  end

  def test_student_cannot_edit_own_comment_after_10_minutes
    project = Project.first
    user = project.student
    task_definition = project.unit.task_definitions.first

    add_auth_header_for(user: user)
    post_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment: 'Original comment'
    assert_equal 201, last_response.status

    comment_id = last_response_body['id']

    travel_to 11.minutes.from_now do
      put_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments/#{comment_id}", comment: 'Too late'
      assert_equal 403, last_response.status, last_response.body
    end

    assert_equal 'Original comment', TaskComment.find(comment_id).read_attribute(:comment)
  end

  def test_student_cannot_edit_other_users_comment
    project = Project.first
    task_definition = project.unit.task_definitions.first
    tutor = project.tutor_for(task_definition)
    user = project.student
    task = project.task_for_task_definition(task_definition)
    comment = task.add_text_comment(tutor, 'Tutor comment')

    add_auth_header_for(user: user)
    put_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments/#{comment.id}", comment: 'Edited by student'

    assert_equal 403, last_response.status, last_response.body
    assert_equal 'Tutor comment', comment.reload.read_attribute(:comment)
  end

  def test_special_task_comments_cannot_be_deleted
    project = FactoryBot.create(:project)
    task_definition = project.unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)
    tutor = project.tutor_for(task_definition)
    student = project.student

    submission_history = FactoryBot.create(:submission_history, task: task)
    overseer_assessment = FactoryBot.create(
      :overseer_assessment,
      task: task,
      submission_history: submission_history,
      submission_timestamp: submission_history.submission_timestamp,
      status: :failed
    )

    protected_comments = [
      task.add_status_comment(student, TaskStatus.ready_for_feedback),
      task.add_discussed_comment(tutor),
      task.add_feedback_review_request_comment(student),
      AssessmentComment.create!(
        task: task,
        user: tutor,
        recipient: student,
        comment: 'Automated tests failed',
        commentable: overseer_assessment
      )
    ]

    protected_comments.each do |comment|
      add_auth_header_for(user: comment.user)
      delete_json "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments/#{comment.id}"
      assert_equal 403, last_response.status, "Expected #{comment.class.name} delete to be rejected"
    end

    deleted_comment_types = protected_comments.reject { |comment| TaskComment.exists?(comment.id) }.map(&:content_type)

    assert_empty deleted_comment_types, "Expected protected comment types to remain after delete attempt: #{deleted_comment_types.join(', ')}"
  end

  def test_student_reply_to_other_student_in_same_group
    unit = FactoryBot.create :unit

    group_set = GroupSet.create!(name: 'test_student_reply_to_other_student_in_same_group', unit: unit)
    group_set.save!

    group = Group.create!(group_set: group_set, name: 'test_student_reply_to_other_student_in_same_group', tutorial: unit.tutorials.first)

    group.add_member(unit.active_projects[0])
    group.add_member(unit.active_projects[1])
    group.add_member(unit.active_projects[2])
    group.save!

    project = group.projects.first

    # td = FactoryBot.create(:task_definition, unit: unit, group_set: group_set)
    td = TaskDefinition.new(unit_id: unit.id,
                            tutorial_stream: unit.tutorial_streams.first,
                            name: 'Task to switch from ind to group after submission',
                            description: 'test def',
                            weighting: 4,
                            target_grade: 0,
                            start_date: Time.zone.now - 1.week,
                            target_date: Time.zone.now - 1.day,
                            due_date: Time.zone.now + 1.week,
                            abbreviation: 'TaskSwitchIndGrp',
                            restrict_status_updates: false,
                            upload_requirements: [ { 'key' => 'file0', 'name' => 'Shape Class', 'type' => 'code' } ],
                            plagiarism_warn_pct: 0.8,
                            is_graded: false,
                            max_quality_pts: 0,
                            group_set: group_set)
    td.save!

    # Add auth_token and username to header
    add_auth_header_for(user: group.projects.first.student)

    # Student 1 in group post first comment
    post_json "/api/projects/#{project.id}/task_def_id/#{td.id}/comments", comment: 'Hello World'
    assert_equal 'Hello World', last_response_body['comment']

    assert_equal 201, last_response.status
    id = last_response_body['id']

    # Add auth_token and username to header
    project = group.projects.second
    add_auth_header_for(user: project.student)

    # Student 2 in group replies
    post_json "/api/projects/#{project.id}/task_def_id/#{td.id}/comments", comment: 'Hello World 2', reply_to_id: id
    assert_equal 'Hello World 2', last_response_body['comment'], last_response_body.inspect
    assert_equal 201, last_response.status
  end

  def test_student_reply_to_other_student_in_different_group
    campus = FactoryBot.create(:campus)
    unit = FactoryBot.create :unit
    # project_1 = FactoryBot.create(:project, unit: unit, campus: campus)

    group_set = GroupSet.create!(name: 'test_student_reply_to_other_student_in_same_group', unit: unit)
    group_set.save!

    group_1 = Group.create!(group_set: group_set, name: 'test_1', tutorial: unit.tutorials.first)

    group_1.add_member(unit.active_projects[0])
    group_1.save!

    group_2 = Group.create!(group_set: group_set, name: 'test_2', tutorial: unit.tutorials.first)

    group_2.add_member(unit.active_projects[1])
    group_2.save!

    project = group_1.projects.first

    td = FactoryBot.create(:task_definition, unit: unit, group_set: group_set)

    # Add auth_token and username to header
    add_auth_header_for(user: unit.active_projects[0].student)

    # Student 1 in group post first comment
    post_json "/api/projects/#{project.id}/task_def_id/#{td.id}/comments", comment: 'Hello World'
    # assert_equal last_response, "test"
    assert_equal 201, last_response.status
    id = last_response_body['id']

    # Add auth_token and username to header
    add_auth_header_for(user: unit.active_projects[1].student)

    # Student 2 in group 2 replies
    post_json "/api/projects/#{project.id}/task_def_id/#{td.id}/comments", comment: 'Hello World 2', reply_to_id: id
    # assert_equal last_response, "test"
    assert_equal 403, last_response.status
  end

  def test_convenor_reply_in_wrong_unit
    campus = FactoryBot.create(:campus)
    unit_1 = FactoryBot.create(:unit, student_count: 2)
    unit_1.employ_staff(User.first, Role.convenor)
    project_1 = FactoryBot.create(:project, unit: unit_1, campus: campus)
    student_1 = project_1.student
    task_definition_1 = unit_1.task_definitions.first

    # Add auth_token and username to header
    add_auth_header_for(user: student_1)

    # Student makes a comment on task 1 in unit 1
    post_json "/api/projects/#{project_1.id}/task_def_id/#{task_definition_1.id}/comments", comment: 'Hello World'
    assert_equal 201, last_response.status
    id = last_response_body['id']

    unit_2 = FactoryBot.create(:unit, student_count: 2)
    project_2 = FactoryBot.create(:project, unit: unit_2, campus: campus)
    task_definition_2 = unit_2.task_definitions.first
    unit_2.employ_staff(User.first, Role.convenor)

    # Add auth_token and username to header
    add_auth_header_for(user: User.first)

    # Convenor replies to that comment in a different unit/projet
    post_json "/api/projects/#{project_2.id}/task_def_id/#{task_definition_2.id}/comments", comment: 'Hello World', reply_to_id: id
    assert_equal 404, last_response.status
  end

  def test_student_post_image_comment
    project = Project.first
    user = project.student
    unit = project.unit
    task_definition = unit.task_definitions.first

    pre_count = TaskComment.count

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    comment_data = { attachment: upload_file('test_files/submissions/Deakin_Logo.jpeg', 'image/jpeg') }

    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 201, last_response.status

    assert_equal pre_count + 1, TaskComment.count, 'one comment added'

    new_comment = TaskComment.last

    assert_equal 'image comment', new_comment.comment, 'last comment has message'
    assert File.exist?(new_comment.attachment_path)

    new_comment.destroy
  end

  def test_student_post_gif_comment
    project = Project.first
    user = project.student
    unit = project.unit
    task_definition = unit.task_definitions.first

    pre_count = TaskComment.count

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    comment_data = { attachment: upload_file('test_files/submissions/unbelievable.gif', 'image/gif') }

    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 201, last_response.status

    assert_equal pre_count + 1, TaskComment.count, 'one comment added'

    new_comment = TaskComment.last

    assert_equal 'image comment', new_comment.comment, 'last comment has message'
    assert File.exist?(new_comment.attachment_path)
    assert_equal '.gif', new_comment.attachment_extension, 'attachment is a gif'

    new_comment.destroy
  end

  def test_student_post_pdf_comment
    project = Project.first
    user = project.student
    unit = project.unit
    task_definition = unit.task_definitions.first

    pre_count = TaskComment.count

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    comment_data = { attachment: upload_file('test_files/submissions/00_question.pdf', 'application/pdf') }

    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 201, last_response.status

    assert_equal pre_count + 1, TaskComment.count, 'one comment added'

    new_comment = TaskComment.last

    assert_equal 'pdf document', new_comment.comment, 'last comment has message'
    assert File.exist?(new_comment.attachment_path)
    assert_equal '.pdf', new_comment.attachment_extension, 'attachment is a pdf'

    new_comment.destroy
  end

  def test_comment_attachments_deleted
    project = Project.first
    user = project.student
    unit = project.unit
    task_definition = unit.task_definitions.first

    pre_count = TaskComment.count

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    comment_data = { attachment: upload_file('test_files/submissions/00_question.pdf', 'application/pdf') }

    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 201, last_response.status

    assert_equal pre_count + 1, TaskComment.count, 'one comment added'

    new_comment = TaskComment.last

    assert File.exist?(new_comment.attachment_path)

    new_comment.destroy
    assert_not File.exist?(new_comment.attachment_path)
  end

  def test_post_comment_empty_attachment
    project = Project.first
    user = project.student
    unit = project.unit
    task_definition = unit.task_definitions.first

    pre_count = TaskComment.count

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    comment_data = { attachment: upload_file('test_files/submissions/boo.png', 'image/png') }

    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", comment_data

    assert_equal 400, last_response.status, last_response_body

    assert_equal pre_count, TaskComment.count, 'No comment should be created'
    assert_equal 'Attachment is empty.', last_response_body['error']
  end

  def test_post_comment_oversized_attachment
    project = Project.first
    task_definition = project.unit.task_definitions.first
    pre_count = TaskComment.count

    add_auth_header_for(user: project.student)

    attachment = upload_file('test_files/submissions/00_question.pdf', 'application/pdf')
    File.stub :size?, 30_000_001 do
      post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments", { attachment: attachment }
    end

    assert_equal 413, last_response.status, last_response_body
    assert_equal pre_count, TaskComment.count, 'No comment should be created'
    assert_equal 'Attachment exceeds the maximum attachment size of 30MB.', last_response_body['error']
  end

  # Builds a group task definition for the given group_set.
  def make_group_task_definition(unit, group_set)
    td = TaskDefinition.new(unit_id: unit.id,
                            tutorial_stream: unit.tutorial_streams.first,
                            name: "pr_file_01_group_task_#{group_set.id}",
                            description: 'group attachment access',
                            weighting: 4,
                            target_grade: 0,
                            start_date: Time.zone.now - 1.week,
                            target_date: Time.zone.now - 1.day,
                            due_date: Time.zone.now + 1.week,
                            abbreviation: "PRFILE01_#{group_set.id}",
                            restrict_status_updates: false,
                            upload_requirements: [ { 'key' => 'file0', 'name' => 'Doc', 'type' => 'document' } ],
                            plagiarism_warn_pct: 0.8,
                            is_graded: false,
                            max_quality_pts: 0,
                            group_set: group_set)
    td.save!
    td
  end

  # Builds a single group of `members` and returns [unit, group, task_definition].
  def build_group_task(members: 2)
    unit = FactoryBot.create :unit
    group_set = GroupSet.create!(name: 'pr_file_01_group_set', unit: unit)
    group = Group.create!(group_set: group_set, name: 'pr_file_01_group', tutorial: unit.tutorials.first)
    members.times { |i| group.add_member(unit.active_projects[i]) }
    group.save!

    [unit, group, make_group_task_definition(unit, group_set)]
  end

  # A group member posts an image attachment. Another member of the same group must be
  # able to open it. The attachment is on the author's task instance, but the whole group
  # shares one group_submission, so the fetch has to look through all_comments, not the
  # caller's own task's comments (which was returning ActiveRecord::RecordNotFound -> 404).
  def test_group_member_can_open_another_members_attachment
    _unit, group, td = build_group_task

    author = group.projects.first
    reader = group.projects.second

    add_auth_header_for(user: author.student)
    post "/api/projects/#{author.id}/task_def_id/#{td.id}/comments",
         { attachment: upload_file('test_files/submissions/Deakin_Logo.jpeg', 'image/jpeg') }
    assert_equal 201, last_response.status, last_response.body
    comment_id = last_response_body['id']

    # The other member opens the attachment through their own project.
    add_auth_header_for(user: reader.student)
    get "/api/projects/#{reader.id}/task_def_id/#{td.id}/comments/#{comment_id}"
    assert_equal 200, last_response.status, last_response.body

    TaskComment.find(comment_id).destroy
  end

  # The widened lookup must stay bounded to the caller's own group. A member of a
  # different group in the same group_set, querying their own project (so the :get
  # check passes), still cannot reach the first group's comment: all_comments is scoped
  # by that caller's own group_submission, so the id is not found and the API returns 404.
  def test_attachment_lookup_stays_within_callers_group
    unit = FactoryBot.create :unit
    group_set = GroupSet.create!(name: 'pr_file_01_two_groups', unit: unit)
    group_a = Group.create!(group_set: group_set, name: 'pr_file_01_group_a', tutorial: unit.tutorials.first)
    group_b = Group.create!(group_set: group_set, name: 'pr_file_01_group_b', tutorial: unit.tutorials.first)
    group_a.add_member(unit.active_projects[0])
    group_b.add_member(unit.active_projects[1])
    td = make_group_task_definition(unit, group_set)

    author = group_a.projects.first
    outsider = group_b.projects.first

    add_auth_header_for(user: author.student)
    post "/api/projects/#{author.id}/task_def_id/#{td.id}/comments",
         { attachment: upload_file('test_files/submissions/Deakin_Logo.jpeg', 'image/jpeg') }
    assert_equal 201, last_response.status, last_response.body
    comment_id = last_response_body['id']

    # The other group's member posts on their own group task, so their task and
    # group_submission exist, then tries to open group A's attachment.
    add_auth_header_for(user: outsider.student)
    post_json "/api/projects/#{outsider.id}/task_def_id/#{td.id}/comments", comment: 'group b note'
    assert_equal 201, last_response.status, last_response.body

    get "/api/projects/#{outsider.id}/task_def_id/#{td.id}/comments/#{comment_id}"
    assert_equal 404, last_response.status, last_response.body

    TaskComment.find(comment_id).destroy
  end

  def test_read_receipts_for_task_status_comments
    project = Project.first
    user = project.student
    unit = project.unit

    td = TaskDefinition.new(unit_id: unit.id,
                            tutorial_stream: unit.tutorial_streams.first,
                            name: 'test_read_receipts_for_task_status_comments',
                            description: 'test_read_receipts_for_task_status_comments',
                            weighting: 4,
                            target_grade: 0,
                            start_date: Time.zone.now - 2.weeks,
                            target_date: Time.zone.now + 1.week,
                            due_date: Time.zone.now + 2.weeks,
                            abbreviation: 'test_read_receipts_for_task_status_comments',
                            restrict_status_updates: false,
                            upload_requirements: [ ],
                            plagiarism_warn_pct: 0.8,
                            is_graded: false,
                            max_quality_pts: 0)
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    # Add auth_token and username to header
    add_auth_header_for(user: user)

    # Make a submission for this student
    post_json "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post
    assert_equal 201, last_response.status

    task = project.task_for_task_definition(td)
    assert_equal TaskStatus.ready_for_feedback, task.task_status

    refute task.comments.last.new_for?(user)
    refute task.comments.last.new_for?(project.tutor_for(td))

    td.destroy!
  end

  def test_project_plan_task_comments_dont_show_in_inbox
    project = Project.first
    user = project.student
    unit = project.unit
    unit.update(allow_flexible_dates: true)

    td = TaskDefinition.new(unit_id: unit.id,
                            tutorial_stream: unit.tutorial_streams.first,
                            name: 'test_project_plan_task_comments_dont_show_in_inbox',
                            description: 'test_project_plan_task_comments_dont_show_in_inbox',
                            weighting: 4,
                            target_grade: 0,
                            start_date: Time.zone.now - 2.weeks,
                            target_date: Time.zone.now + 1.week,
                            due_date: Time.zone.now + 2.weeks,
                            abbreviation: 'test_project_plan_task_comments_dont_show_in_inbox',
                            restrict_status_updates: false,
                            upload_requirements: [],
                            plagiarism_warn_pct: 0.8,
                            is_graded: false,
                            max_quality_pts: 0)
    td.save!

    task_new = Task.create!(
      project_id: project.id,
      task_definition_id: td.id,
      task_status: TaskStatus.not_started
    )

    data_to_post = {
      extensions: 0
    }

    add_auth_header_for(user: project.student)
    put "/api/projects/#{project.id}/task_def_id/#{td.id}/plan", data_to_post
    assert_equal 200, last_response.status

    task_new.reload

    inbox = unit.tasks_for_task_inbox(unit.tutors.first)
    assert_not_includes inbox.map(&:id), task_new.id, "Task should not be in tutors inbox"
    assert_not task_new.comments.last.new_for?(user), "Comment should be marked read by student"
    assert_not task_new.comments.last.new_for?(project.tutor_for(td)), "Comment should be read by tutor"

    td.destroy!
    unit.update(allow_flexible_dates: false)
  end

  def test_discussed_in_class_task_comments_dont_show_in_inbox
    project = Project.first
    user = project.student
    unit = project.unit

    td = TaskDefinition.new(unit_id: unit.id,
                            tutorial_stream: unit.tutorial_streams.first,
                            name: 'test_discussed_in_class_task_comments_dont_show_in_inbox',
                            description: 'test_discussed_in_class_task_comments_dont_show_in_inbox',
                            weighting: 4,
                            target_grade: 0,
                            start_date: Time.zone.now - 2.weeks,
                            target_date: Time.zone.now + 1.week,
                            due_date: Time.zone.now + 2.weeks,
                            abbreviation: 'test_discussed_in_class_task_comments_dont_show_in_inbox',
                            restrict_status_updates: false,
                            upload_requirements: [],
                            plagiarism_warn_pct: 0.8,
                            is_graded: false,
                            max_quality_pts: 0)
    td.save!

    task_new = Task.create!(
      project_id: project.id,
      task_definition_id: td.id,
      task_status: TaskStatus.not_started
    )

    task_new.add_discussed_comment(unit.tutors.first)
    task_new.reload

    inbox = unit.tasks_for_task_inbox(unit.tutors.first)
    assert_not_includes inbox.map(&:id), task_new.id, "Task should not be in tutors inbox"
    assert_not task_new.comments.last.new_for?(user), "Comment should be marked read by student"
    assert_not task_new.comments.last.new_for?(project.tutor_for(td)), "Comment should be read by tutor"

    task_new.add_text_comment(user, "test comment")

    inbox = unit.tasks_for_task_inbox(unit.tutors.first)
    assert_includes inbox.map(&:id), task_new.id, "Task should not be in tutors inbox"
    assert task_new.comments.last.new_for?(project.tutor_for(td)), "Comment should not be read by tutor"

    td.destroy!
  end

  # Marking a comment as unread must delete the caller's read receipt and succeed.
  # remove_comment_read_entry used to call delete_all with a conditions hash, which raises
  # ArgumentError on Rails 8 and turned every mark-as-unread into a 500.
  def test_mark_comment_as_unread_removes_the_read_receipt
    project = FactoryBot.create(:project)
    unit = project.unit
    user = project.student
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)

    comment = task.add_text_comment(convenor, 'Please look at this')
    comment.mark_as_read(user)
    assert comment.read_by?(user), 'Comment should be read before it is marked unread'
    assert_equal 1, CommentsReadReceipts.where(user: user, task_comment: comment).count

    add_auth_header_for user: user
    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments/#{comment.id}"

    assert_equal 201, last_response.status, last_response_body
    assert_equal 0, CommentsReadReceipts.where(user: user, task_comment: comment).count, 'Read receipt should be gone'
    assert_not comment.reload.read_by?(user), 'Comment should be unread after the request'
  end

  def test_group_member_can_mark_shared_comment_unread_without_affecting_other_receipts
    fixture = grouped_comment_fixture
    comment = fixture[:comment]
    author = fixture[:first_project].student
    caller = fixture[:second_project].student

    comment.mark_as_read(caller)
    assert comment.read_by?(author), "the comment author's receipt should exist"
    assert comment.read_by?(caller), "the other group member's receipt should exist"

    add_auth_header_for user: caller
    post "/api/projects/#{fixture[:second_project].id}/task_def_id/#{fixture[:task_definition].id}/comments/#{comment.id}"

    assert_equal 201, last_response.status, last_response_body
    assert_not comment.reload.read_by?(caller), "only the caller's receipt should be removed"
    assert comment.read_by?(author), "another group member's receipt must remain"
  end

  def test_member_of_another_group_cannot_mark_comment_unread
    fixture = grouped_comment_fixture
    comment = fixture[:comment]
    outsider = fixture[:other_project].student

    # Give the other group its own submission so all_comments is explicitly
    # scoped to that group submission rather than the individual task.
    fixture[:other_project]
      .task_for_task_definition(fixture[:task_definition])
      .ensured_group_submission

    comment.mark_as_read(outsider)
    assert comment.read_by?(outsider)

    add_auth_header_for user: outsider
    post "/api/projects/#{fixture[:other_project].id}/task_def_id/#{fixture[:task_definition].id}/comments/#{comment.id}"

    assert_equal 404, last_response.status, last_response_body
    assert comment.reload.read_by?(outsider), 'a rejected request must not change receipts'
  end

  # A user with no submission rights on the project cannot mark its comments unread.
  def test_mark_comment_as_unread_rejects_an_unauthorised_user
    project = FactoryBot.create(:project)
    unit = project.unit
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)
    comment = task.add_text_comment(convenor, 'Private thread')

    outsider = FactoryBot.create(:project).student

    add_auth_header_for user: outsider
    post "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/comments/#{comment.id}"

    assert_equal 403, last_response.status, last_response_body
  end

  private

  def grouped_comment_fixture
    unit = FactoryBot.create(:unit, student_count: 3, task_count: 0)
    first_project, second_project, other_project = unit.active_projects.first(3)
    group_set = FactoryBot.create(:group_set, unit: unit)
    shared_group = FactoryBot.create(:group, group_set: group_set, tutorial: unit.tutorials.first)
    other_group = FactoryBot.create(:group, group_set: group_set, tutorial: unit.tutorials.first)

    shared_group.add_member(first_project)
    shared_group.add_member(second_project)
    other_group.add_member(other_project)

    task_definition = FactoryBot.create(
      :task_definition,
      unit: unit,
      group_set: group_set,
      outcome_count: 0
    )
    task = first_project.task_for_task_definition(task_definition)
    comment = task.add_text_comment(first_project.student, 'Shared group feedback')

    {
      first_project: first_project,
      second_project: second_project,
      other_project: other_project,
      task_definition: task_definition,
      comment: comment
    }
  end
end
