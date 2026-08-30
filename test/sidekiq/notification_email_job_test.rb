# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class NotificationEmailJobTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear
  end

  def test_perform_delivers_the_notification_email
    notification = FactoryBot.create(
      :notification,
      event: 'general',
      message: 'EN-F03 job delivery test.'
    )

    assert_difference(
      -> { ActionMailer::Base.deliveries.count },
      1
    ) do
      NotificationEmailJob.new.perform(notification.id)
    end

    mail = ActionMailer::Base.deliveries.last
    body = if mail.multipart?
             mail.parts.map { |part| part.body.decoded }.join("\n")
           else
             mail.body.decoded
           end
    expected_subject = "#{Doubtfire::Application.config.institution[:product_name]}: New notification"

    assert_equal [notification.user.email], mail.to
    assert_equal expected_subject, mail.subject
    assert_includes body, notification.message
  end

  def test_missing_notification_is_raised_so_a_pre_commit_race_is_retried
    assert_no_difference(
      -> { ActionMailer::Base.deliveries.count }
    ) do
      assert_raises(ActiveRecord::RecordNotFound) do
        NotificationEmailJob.new.perform(-1)
      end
    end
  end

  def test_the_job_runs_on_the_mailers_queue
    # Student facing email must not queue behind PDF and CSV work on default.
    # The worker has to be listening on this queue, see doubtfire-deploy#10.
    assert_equal 'mailers', NotificationEmailJob.get_sidekiq_options['queue'].to_s
  end

  def test_no_delivery_when_the_preference_was_turned_off_after_queueing
    user = FactoryBot.create(:user, receive_feedback_notifications: true)
    notification = FactoryBot.create(
      :notification,
      :feedback,
      user: user,
      event: 'task_comment_created',
      message: 'Queued while the category was still on.'
    )

    # retry: 3 means the job can run well after it was queued.
    user.update!(receive_feedback_notifications: false)

    assert_no_difference(
      -> { ActionMailer::Base.deliveries.count }
    ) do
      NotificationEmailJob.new.perform(notification.id)
    end
  end

  def test_a_type_without_a_preference_is_still_delivered
    user = FactoryBot.create(
      :user,
      receive_task_notifications: false,
      receive_feedback_notifications: false,
      receive_portfolio_notifications: false
    )
    notification = FactoryBot.create(
      :notification,
      user: user,
      event: 'general',
      message: 'General notices ignore the category toggles.'
    )

    assert_difference(
      -> { ActionMailer::Base.deliveries.count },
      1
    ) do
      NotificationEmailJob.new.perform(notification.id)
    end
  end

  def test_delivery_failure_is_raised_so_sidekiq_can_retry
    notification = FactoryBot.create(
      :notification,
      event: 'general'
    )
    failing_delivery = Class.new do
      def deliver_now
        raise 'smtp unavailable'
      end
    end.new

    NotificationsMailer.stub(:single_notification, ->(_notification) { failing_delivery }) do
      error = assert_raises(RuntimeError) do
        NotificationEmailJob.new.perform(notification.id)
      end
      assert_equal 'smtp unavailable', error.message
    end
  end

  def test_async_payload_contains_only_the_notification_id
    notification = FactoryBot.create(
      :notification,
      event: 'general'
    )
    jid = NotificationEmailJob.perform_async(notification.id)
    job = NotificationEmailJob.jobs.find do |candidate|
      candidate['jid'] == jid
    end

    assert_not_nil job
    assert_equal 'NotificationEmailJob', job['class']
    assert_equal 'mailers', job['queue']
    assert_equal [notification.id], job['args']
    assert_equal 0, ActionMailer::Base.deliveries.count
  end
end
