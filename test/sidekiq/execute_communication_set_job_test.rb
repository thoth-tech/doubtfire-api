# frozen_string_literal: true

require 'test_helper'

class ExecuteCommunicationSetJobTest < ActiveSupport::TestCase
  def test_task_comment_action_adds_a_comment_to_each_selected_students_task
    unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 1,
      stream_count: 0,
      tutorials: 0,
      outcome_count: 0,
      staff_count: 1
    )

    task_definition = unit.task_definitions.first
    campus = Campus.first
    comment_author = unit.main_convenor_user

    student_one = FactoryBot.create(:user, :student)
    student_one.update!(first_name: 'Ada', last_name: 'Lovelace')
    project_one = unit.enrol_student(student_one, campus)

    student_two = FactoryBot.create(:user, :student)
    student_two.update!(first_name: 'Grace', last_name: 'Hopper')
    project_two = unit.enrol_student(student_two, campus)

    communication_set = unit.communication_sets.create!(name: 'Test Set', active: true)
    communication_rule = communication_set.communication_rules.create!(
      name: 'Comment Rule',
      operator: 'and',
      position: 0
    )
    communication_rule.communication_actions.create!(
      type: 'TaskCommentAction',
      task_definition: task_definition,
      body: 'Please review {{student.first_name}} for {{unit.code}}'
    )

    ExecuteCommunicationSetJob.new.perform(communication_set.id)

    task_one = project_one.task_for_task_definition(task_definition)
    task_two = project_two.task_for_task_definition(task_definition)

    assert_equal 1, TaskComment.where(task: task_one).count
    assert_equal 1, TaskComment.where(task: task_two).count

    comment_one = task_one.comments.last
    comment_two = task_two.comments.last

    assert_equal comment_author, comment_one.user
    assert_equal comment_author, comment_two.user
    assert_equal 'Please review Ada for ' + unit.code, comment_one.comment
    assert_equal 'Please review Grace for ' + unit.code, comment_two.comment
  end

  # Builds a unit with three enrolled students and a set that emails all of them.
  def email_set_with_three_students
    unit = FactoryBot.create(
      :unit,
      with_students: false,
      task_count: 1,
      stream_count: 0,
      tutorials: 0,
      outcome_count: 0,
      staff_count: 1
    )

    campus = Campus.first
    projects = %w[Ada Grace Katherine].map do |first_name|
      student = FactoryBot.create(:user, :student)
      student.update!(first_name: first_name)
      unit.enrol_student(student, campus)
    end

    communication_set = unit.communication_sets.create!(name: 'Email Set', active: true)
    communication_rule = communication_set.communication_rules.create!(
      name: 'Email Rule',
      operator: 'and',
      position: 0
    )
    communication_rule.communication_actions.create!(
      type: 'EmailStudentAction',
      subject: 'A message about {{unit.code}}',
      body: 'Hello {{student.first_name}}'
    )

    [communication_set, projects]
  end

  # Replaces the mailer for the duration of the block so that the nth delivery
  # raises the way an unroutable address does.
  def with_delivery_failing_on(nth)
    original = CommunicationsMailer.method(:communication_email)
    calls = 0

    CommunicationsMailer.define_singleton_method(:communication_email) do |**kwargs|
      calls += 1
      if calls == nth
        failing = Object.new
        failing.define_singleton_method(:deliver_now) { raise 'mailbox unavailable' }
        failing
      else
        original.call(**kwargs)
      end
    end

    yield
  ensure
    CommunicationsMailer.singleton_class.send(:remove_method, :communication_email)
    CommunicationsMailer.define_singleton_method(:communication_email, original)
  end

  # Runs the job while capturing the payload it would store, which is the record
  # a convenor sees of the run.
  def perform_capturing_result(communication_set_id)
    job = ExecuteCommunicationSetJob.new
    captured = nil
    job.define_singleton_method(:store) { |payload| captured = payload }
    job.perform(communication_set_id)
    captured
  end

  # One bad address used to abort the run, and the retry started again from the
  # first student, so everyone already emailed got a second copy.
  def test_one_failed_delivery_does_not_stop_the_rest_of_the_run
    communication_set, projects = email_set_with_three_students
    ActionMailer::Base.deliveries.clear

    result = with_delivery_failing_on(2) do
      perform_capturing_result(communication_set.id)
    end

    assert_equal 2, ActionMailer::Base.deliveries.count

    email_rows = result[:result][:actions].select { |row| row[:action_type] == 'EmailStudentAction' }
    failed = email_rows.select { |row| row[:status] == 'failed' }

    assert_equal 1, failed.count
    assert_equal 2, email_rows.count { |row| row[:status] == 'sent' }
    assert_equal 'mailbox unavailable', failed.first[:reason]
    assert_includes projects.map(&:id), failed.first[:project_id]

    rule = communication_set.communication_rules.first
    csv = ExecuteCommunicationSetJob.new.send(:build_action_log_csv, rule, projects, email_rows)
    failed_csv_row = CSV.parse(csv, headers: true).find { |row| row['status'] == 'failed' }

    assert_not_nil failed_csv_row
    assert_equal(
      "Failed to send email to #{failed.first[:recipient_email]}: mailbox unavailable",
      failed_csv_row['details']
    )
  end

  # The check on an over-eager rescue. Nothing about a clean run changes.
  def test_a_run_with_no_failures_is_unchanged
    communication_set, projects = email_set_with_three_students
    ActionMailer::Base.deliveries.clear

    result = perform_capturing_result(communication_set.id)

    assert_equal 3, ActionMailer::Base.deliveries.count

    email_rows = result[:result][:actions].select { |row| row[:action_type] == 'EmailStudentAction' }
    assert_equal 3, email_rows.count { |row| row[:status] == 'sent' }
    assert_empty email_rows.select { |row| row[:status] == 'failed' }
    assert_equal projects.length, email_rows.length
  end

  # Documents honestly what this change does not fix. There is still no record of
  # who has already been sent to, so running the set again mails everyone again.
  # A per-recipient delivery ledger is a separate ticket.
  def test_a_second_run_still_mails_everyone_again
    communication_set, = email_set_with_three_students
    ActionMailer::Base.deliveries.clear

    with_delivery_failing_on(2) do
      perform_capturing_result(communication_set.id)
    end
    assert_equal 2, ActionMailer::Base.deliveries.count

    perform_capturing_result(communication_set.id)
    assert_equal 5, ActionMailer::Base.deliveries.count
  end
end
