require 'test_helper'
require 'minitest/mock'

class SubmissionLifecycleTest < ActiveSupport::TestCase
  setup do
    @unit = FactoryBot.create(:unit, student_count: 2, task_count: 1,
                             start_date: Time.current - 6.weeks, end_date: Time.current + 10.weeks)
    @unit.update!(extension_weeks_on_resubmit_request: 1, allow_flexible_dates: false)
    @definition = @unit.task_definitions.first
    @definition.update!(start_date: @unit.start_date, target_date: Time.current - 3.weeks, due_date: @unit.end_date, target_grade: 0)
    @task = @unit.active_projects.first.task_for_task_definition(@definition)
    @staff = @unit.main_convenor_user
  end

  test 'task opt out preserves existing dates and can be enabled for future feedback' do
    assert @definition.resubmission_extensions_enabled
    @definition.update!(resubmission_extensions_enabled: false)
    previous_date = @task.effective_deadline
    @task.assess(TaskStatus.fix_and_resubmit, @staff)
    assert_equal previous_date, @task.reload.effective_deadline
    assert_empty deadline_notifications
    @definition.update!(resubmission_extensions_enabled: true)
    @task.assess(TaskStatus.discuss, @staff)
    assert_equal 1, @task.reload.extensions
    assert_equal 1, deadline_notifications.count
    @definition.update!(resubmission_extensions_enabled: false)
    assert_equal 1, @task.reload.extensions, 'Opting out must not revoke an existing extension'
  end

  test 'replayed assessments use one existing notification event and safe message' do
    @task.assess(TaskStatus.fix_and_resubmit, @staff)
    @task.assess(TaskStatus.discuss, @staff)
    assert_equal 1, @task.reload.extensions
    assert_equal 1, deadline_notifications.count
    notification = deadline_notifications.first
    assert_equal @task.project.student, notification.user
    assert_equal @task.resubmission_extension_comment, notification.notifiable
    assert_includes notification.message, @task.effective_deadline_date.iso8601
    assert_equal "Your task deadline is now #{@task.effective_deadline_date.iso8601} (end of day anywhere on earth) after feedback requiring further action. Open OnTrack for details.", notification.message
    assert_includes notification.link, ERB::Util.url_encode(@definition.abbreviation)
    NotificationService.deliver(notification)
    assert_equal 1, deadline_notifications.count
  end

  test 'archive marker failure rolls back both the deadline and notification' do
    @task.stub(:record_resubmission_extension, ->(*) { raise 'simulated persistence failure' }) do
      assert_raises(RuntimeError) { @task.assess(TaskStatus.fix_and_resubmit, @staff) }
    end
    assert_equal 0, @task.reload.extensions
    assert_nil @task.resubmission_extension_comment
    assert_empty deadline_notifications
  end

  test 'notification reservation failure rolls back extension and replay marker' do
    NotificationService.stub(:reserve, ->(**) { raise 'simulated notification persistence failure' }) do
      assert_raises(RuntimeError) { @task.assess(TaskStatus.fix_and_resubmit, @staff) }
    end
    assert_equal 0, @task.reload.extensions
    assert_nil @task.resubmission_extension_comment
    assert_empty deadline_notifications
  end

  test 'a stale duplicate assessment without an original submission date cannot earn a second extension' do
    stale_task = Task.find(@task.id)
    @task.assess(TaskStatus.fix_and_resubmit, @staff, Time.current - 1.minute)
    stale_task.assess(TaskStatus.fix_and_resubmit, @staff, Time.current)
    assert_equal 1, @task.reload.extensions
    assert_equal 1, deadline_notifications.count
  end

  test 'task api and calendar use the same date and stable event after feedback' do
    calendar = @task.project.student.create_webcal!(guid: SecureRandom.uuid)
    before = calendar.to_ical.events.find { |event| event.uid == "E-#{@definition.id}" }
    @task.assess(TaskStatus.rediscuss, @staff)
    @task.reload
    response = Entities::TaskEntity.represent(@task, update_only: true).as_json
    assert_equal @task.effective_deadline_date.iso8601, response[:effective_deadline_date]
    assert_equal 'post_feedback_extension', response[:effective_deadline_reason]
    assert_equal @task.resubmission_extension_comment.id, response[:effective_deadline_source_id]
    after = calendar.reload.to_ical.events.find { |event| event.uid.to_s == before.uid.to_s }
    assert_equal @task.effective_deadline_date, after.dtstart.to_date
    assert_equal before.uid.to_s, after.uid.to_s
    assert_not_equal before.dtstart, after.dtstart
  end

  test 'task api omits an effective deadline date when shallow task data has no date' do
    task_data = {
      id: @task.id,
      task_definition_id: @definition.id,
      due_date: @task.due_date,
      effective_deadline_date: nil
    }

    response = Entities::TaskEntity.represent(task_data).as_json

    assert_not response.key?(:effective_deadline_date)
  end

  test 'unit disable and flexible dates do not raise automatic notifications' do
    @unit.update!(extension_weeks_on_resubmit_request: 0)
    @task.reload
    @task.assess(TaskStatus.demonstrate, @staff)
    assert_empty deadline_notifications
    @unit.update!(extension_weeks_on_resubmit_request: 1, allow_flexible_dates: true)
    @task.reload
    @task.assess(TaskStatus.demonstrate, @staff)
    assert_equal 0, @task.reload.extensions
    assert_empty deadline_notifications
    assert_equal 'flexible_date', @task.effective_deadline_reason
  end

  test 'group feedback extends and notifies each affected student only once' do
    group_set = FactoryBot.create(:group_set, unit: @unit)
    group = FactoryBot.create(:group, group_set: group_set, tutorial: @unit.tutorials.first)
    @definition.update!(group_set: group_set)
    projects = @unit.active_projects.to_a
    projects.each { |project| group.add_member(project, notify: false) }
    submission = GroupSubmission.create!(group: group, task_definition: @definition, submitted_by_project: projects.first)
    tasks = projects.map { |project| project.task_for_task_definition(@definition) }
    tasks.each { |task| task.update!(group_submission: submission) }
    tasks.first.trigger_transition(trigger: 'fix', by_user: @staff)
    tasks.first.trigger_transition(trigger: 'fix', by_user: @staff)
    tasks.each do |task|
      assert_equal 1, task.reload.extensions
      assert_equal 1, Notification.where(user: task.project.student, event: 'resubmission_deadline_changed').count
    end
    assert_equal 1, tasks.map(&:effective_deadline).uniq.length
  end

  test 'each declared feedback outcome grants its first extension' do
    [TaskStatus.fix_and_resubmit, TaskStatus.discuss, TaskStatus.rediscuss, TaskStatus.demonstrate].each do |status|
      @task.comments.where(type: 'ExtensionComment').destroy_all
      @task.update_columns(extensions: 0, submission_date: nil)
      @task.reload.assess(status, @staff)
      assert_equal 1, @task.reload.extensions, "Expected extension for #{status.name}"
      assert_equal status, @task.resubmission_extension_comment.task_status
    end
  end

  private

  def deadline_notifications
    Notification.where(user: @task.project.student, event: 'resubmission_deadline_changed')
  end
end
