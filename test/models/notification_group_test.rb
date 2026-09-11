require 'test_helper'
require 'minitest/mock'
require 'tempfile'

# EN-V05: notify only the affected student when group membership changes.
class NotificationGroupTest < ActiveSupport::TestCase
  include TestHelpers::PushNotificationHelper

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @group = FactoryBot.create(:group, unit: @project.unit)
    @student = @project.student
  end

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
  end

  def test_adding_a_member_notifies_only_that_student
    assert_difference 'Notification.count', 1 do
      @group.add_member(@project)
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_equal 'general', notification.notification_type
    assert_equal 'group_membership_changed', notification.event
    assert_equal(
      "You have been added to group #{@group.name} in #{@project.unit.code}.",
      notification.message
    )
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/groups",
      expected_body: 'Your group membership changed.'
    )

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to

    # Confirms the event-specific template is being used.
    assert_includes delivered_body, 'group membership changed'
    assert_includes delivered_body, notification.message
  end

  def test_removing_a_member_notifies_that_student
    @group.add_member(@project)

    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    assert_difference 'Notification.count', 1 do
      @group.remove_member(@project)
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_equal 'general', notification.notification_type
    assert_equal 'group_membership_changed', notification.event
    assert_includes notification.message, 'removed from'

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_other_group_members_are_not_notified
    other_project = FactoryBot.create(:project, unit: @project.unit)

    @group.add_member(other_project)

    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    assert_difference 'Notification.count', 1 do
      @group.add_member(@project)
    end
    NotificationEmailJob.drain

    notification = Notification.recent_first.first

    assert_equal @student, notification.user
    assert_not_equal other_project.student, notification.user

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
  end

  def test_switch_to_tutorial_sends_tutorial_changes_without_leave_then_join_notifications
    unit = FactoryBot.create(
      :unit,
      group_sets: 1,
      groups: [{ gs: 0, students: 0 }]
    )

    group_set = unit.group_sets.first
    group_set.update!(
      keep_groups_in_same_class: true,
      allow_students_to_manage_groups: true
    )

    group = group_set.groups.first

    project_one = group.tutorial.projects.first
    project_two = group.tutorial.projects.last

    group.add_member(project_one)
    group.add_member(project_two)

    new_tutorial = FactoryBot.create(:tutorial, unit: unit, campus: nil)

    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    assert_difference -> { Notification.where(event: 'tutorial_changed').count }, 2 do
      assert_no_difference -> { Notification.where(event: 'group_membership_changed').count } do
        group.switch_to_tutorial(new_tutorial)
      end
    end
    NotificationEmailJob.drain

    tutorial_notifications = Notification.where(event: 'tutorial_changed').recent_first.limit(2)

    assert_equal(
      [project_one.student.id, project_two.student.id].sort,
      tutorial_notifications.map(&:user_id).sort
    )
    assert_equal 2, ActionMailer::Base.deliveries.count
    assert_equal(
      [project_one.student.email, project_two.student.email].sort,
      ActionMailer::Base.deliveries.flat_map(&:to).sort
    )
  end

  def test_notification_failure_does_not_stop_membership_change
    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification failed' } do
      assert_nothing_raised do
        @group.add_member(@project)
      end
    end

    assert_includes @group.reload.projects, @project
  end

  def test_bulk_csv_import_adds_member_without_notification
    Tempfile.create(['student-groups', '.csv']) do |file|
      file.write("group_name,username\n#{@group.name},#{@student.username}\n")
      file.flush

      notification_calls = 0

      NotificationService.stub :notify, ->(**_kwargs) { notification_calls += 1 } do
        result = @project.unit.import_student_groups_from_csv(
          @group.group_set,
          file.path
        )

        assert_empty result[:errors], result.inspect
        assert_empty result[:ignored], result.inspect
        assert_equal 1, result[:success].count, result.inspect
      end

      assert_equal 0, notification_calls
    end

    assert_includes @group.reload.projects, @project
  end
end
