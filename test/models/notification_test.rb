require 'test_helper'

class NotificationTest < ActiveSupport::TestCase
  def test_the_factory_builds_a_valid_notification_for_every_category
    Notification::TYPES.each do |type|
      notification = FactoryBot.create(:notification, type.to_sym)

      assert notification.persisted?, "a #{type} notification did not save"
      assert_equal type, notification.notification_type
      assert_equal "#{type}_event", notification.event
      assert notification.message.present?
    end
  end

  def test_an_unread_notification_is_in_the_unread_scope
    notification = FactoryBot.create(:notification, :unread)

    assert_nil notification.read_at
    assert_not notification.read?
    assert_includes Notification.unread, notification
  end

  def test_a_read_notification_is_out_of_the_unread_scope
    notification = FactoryBot.create(:notification, :read)

    assert_not_nil notification.read_at
    assert notification.read?
    assert_not_includes Notification.unread, notification
  end

  # NB-02: a notification records what it is about, and reading that thing
  # clears it. Everything below is about the notifiable target.
  class NotificationTargetTest < ActiveSupport::TestCase
    setup do
      ActionMailer::Base.deliveries.clear

      @project = FactoryBot.create(:project)
      @unit = @project.unit
      @task_definition = @unit.task_definitions.first
      @task = @project.task_for_task_definition(@task_definition)
      @student = @project.student
      @tutor = @project.tutor_for(@task_definition)
    end

    # Exactly what the comments endpoint hands to mark_comments_as_read: the
    # task's comments in load order, minus DiscussionComments. Anything looser
    # would test a caller that does not exist and would hide a filtered-out
    # comment whose notification therefore never clears.
    # See app/api/task_comments_api.rb, GET .../comments.
    def comments_the_endpoint_marks_as_read
      @task.all_comments
           .order('created_at ASC')
           .where("TYPE is null OR TYPE != 'DiscussionComment'")
    end

    def test_a_comment_notification_targets_the_comment_and_not_the_task
      comment = @task.add_text_comment(@tutor, 'Have a look at question three.')
      notification = Notification.recent_first.first

      assert_equal 'task_comment_created', notification.event
      assert_equal comment, notification.notifiable
      assert_equal 'TaskComment', notification.notifiable_type
    end

    def test_a_status_change_notification_targets_the_task
      @task.notify_student_of_status_change(@tutor, :tutor, -1)
      notification = Notification.recent_first.first

      assert_equal 'task_status_changed', notification.event
      assert_equal @task, notification.notifiable
      assert_equal 'Task', notification.notifiable_type
    end

    def test_reading_the_comments_clears_the_recipients_comment_notification
      @task.add_text_comment(@tutor, 'Have a look at question three.')
      notification = Notification.recent_first.first

      assert_equal @student, notification.user
      assert_nil notification.read_at, 'guard: the notification must start unread'

      @task.mark_comments_as_read(@student, comments_the_endpoint_marks_as_read)

      assert_not_nil notification.reload.read_at
    end

    def test_reading_the_comments_does_not_clear_another_users_notification
      @task.add_text_comment(@tutor, 'Have a look at question three.')
      notification = Notification.recent_first.first

      # The tutor opening the same task must not clear the student's bell.
      @task.mark_comments_as_read(@tutor, comments_the_endpoint_marks_as_read)

      assert_nil notification.reload.read_at
    end

    def test_reading_the_comments_clears_a_notification_targeted_at_the_task
      @task.notify_student_of_status_change(@tutor, :tutor, -1)
      notification = Notification.recent_first.first

      assert_equal @task, notification.notifiable

      @task.mark_comments_as_read(@student, comments_the_endpoint_marks_as_read)

      assert_not_nil notification.reload.read_at
    end

    def test_a_notification_with_no_target_survives_the_comments_being_read
      notification = FactoryBot.create(:notification, :general, user: @student)

      assert_nil notification.notifiable

      @task.add_text_comment(@tutor, 'Have a look at question three.')
      @task.mark_comments_as_read(@student, comments_the_endpoint_marks_as_read)

      assert_nil notification.reload.read_at
    end

    def test_an_already_read_notification_keeps_its_original_read_at
      comment = @task.add_text_comment(@tutor, 'Have a look at question three.')
      notification = Notification.recent_first.first

      read_three_days_ago = 3.days.ago.change(usec: 0)
      notification.update!(read_at: read_three_days_ago)

      @task.mark_comments_as_read(@student, comments_the_endpoint_marks_as_read)

      assert_equal comment, notification.notifiable
      assert_equal read_three_days_ago.to_i, notification.reload.read_at.to_i
    end

    # The staff path. A tutor's task_submitted notification is about the task,
    # and the tutor opening that task to mark it is the read that clears it.
    #
    # The reload is load bearing. Task delegates target_date to its task
    # definition, and a definition already loaded through the association keeps
    # the factory's dates. Whether those are in the past varies by unit, so
    # without the reload the submission lands on time_exceeded for some units
    # and no tutor is notified at all. The guard turns that into a readable
    # failure instead of a missing notification.
    def submit_for_marking
      @task_definition.update!(
        start_date: 1.week.ago,
        target_date: 1.week.from_now,
        due_date: 3.weeks.from_now
      )
      @task.reload
      @task.trigger_transition(trigger: 'ready_for_feedback', by_user: @student)

      assert_equal TaskStatus.ready_for_feedback, @task.reload.task_status,
                   'guard: the submission has to actually reach ready_for_feedback'
    end

    def test_a_submission_notification_targets_the_task
      submit_for_marking
      notification = Notification.recent_first.first

      assert_equal 'task_submitted', notification.event
      assert_equal @tutor, notification.user
      assert_equal @task, notification.notifiable
      assert_equal 'Task', notification.notifiable_type
    end

    def test_reading_the_comments_clears_the_tutors_submission_notification
      submit_for_marking
      notification = Notification.recent_first.first

      assert_equal @tutor, notification.user
      assert_nil notification.read_at, 'guard: the notification must start unread'

      @task.mark_comments_as_read(@tutor, comments_the_endpoint_marks_as_read)

      assert_not_nil notification.reload.read_at
    end

    # A deleted comment can never appear in the set handed to
    # mark_comments_as_read again, so a notification still pointing at it could
    # never be cleared by reading. It goes when the comment goes.
    def test_deleting_the_target_comment_takes_its_notification_with_it
      comment = @task.add_text_comment(@tutor, 'Have a look at question three.')
      notification = Notification.recent_first.first

      assert_equal comment, notification.notifiable

      comment.destroy!

      assert_not Notification.exists?(notification.id)
    end

    # The other half of the same cascade. A task can be removed with its task
    # definition, and a notification pointing at a task that no longer exists can
    # never be reached, so it goes too.
    def test_deleting_the_target_task_takes_its_notification_with_it
      submit_for_marking
      notification = Notification.recent_first.first

      assert_equal @task, notification.notifiable

      @task.destroy!

      assert_not Notification.exists?(notification.id)
    end

    # An extension comment is a task comment, so it targets itself and clears
    # through the same comment path rather than needing one of its own.
    def assessed_extension
      @unit.update!(auto_apply_extension_before_deadline: false)
      @task_definition.update!(due_date: @task_definition.target_date + 2.weeks)
      @task.reload

      extension = @task.apply_for_extension(@student, 'Please, I was unwell.', 1)

      assert extension.present?, 'guard: the extension request has to be created'
      assert extension.assess_extension(@tutor, true), 'guard: the extension has to be assessed'

      extension
    end

    def test_an_extension_notification_targets_the_extension_comment
      extension = assessed_extension
      notification = Notification.recent_first.first

      assert_equal 'extension_assessed', notification.event
      assert_equal @student, notification.user
      assert_equal extension, notification.notifiable
      assert_equal 'TaskComment', notification.notifiable_type
    end

    def test_reading_the_comments_clears_the_extension_notification
      assessed_extension
      notification = Notification.recent_first.first

      assert_nil notification.read_at, 'guard: the notification must start unread'

      @task.mark_comments_as_read(@student, comments_the_endpoint_marks_as_read)

      assert_not_nil notification.reload.read_at
    end
  end
end
