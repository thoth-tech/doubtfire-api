# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class NotificationEmailJobTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear
    AdditionalNotificationEmailDeliveryJob.clear
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

  def test_verified_additional_address_receives_a_separate_copy_not_a_cc
    user = FactoryBot.create(:user, email: 'primary@example.edu')
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(:notification, user: user, event: 'general')

    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      NotificationEmailJob.new.perform(notification.id)
    end

    copy_job = AdditionalNotificationEmailDeliveryJob.jobs.last
    assert_equal [notification.id, additional.id, additional.verification_version], copy_job['args']
    assert_not_includes copy_job.to_json, additional.email

    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      AdditionalNotificationEmailDeliveryJob.new.perform(*copy_job['args'])
    end

    primary, copy = ActionMailer::Base.deliveries.last(2)
    assert_equal [user.email], primary.to
    assert_equal [additional.email], copy.to
    assert_empty primary.cc.to_a
    assert_empty copy.cc.to_a
  end

  def test_pending_or_removed_address_receives_no_copy
    user = FactoryBot.create(:user)
    AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    notification = FactoryBot.create(:notification, user: user, event: 'general')

    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      NotificationEmailJob.new.perform(notification.id)
    end
    assert_empty AdditionalNotificationEmailDeliveryJob.jobs

    AdditionalNotificationEmailService.remove(user: user)
    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      NotificationEmailJob.new.perform(notification.id)
    end
    assert_empty AdditionalNotificationEmailDeliveryJob.jobs
  end

  def test_an_additional_copy_failure_does_not_fail_the_primary_delivery
    user = FactoryBot.create(:user)
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(:notification, user: user, event: 'general')
    failing_delivery = Class.new do
      def deliver_now
        raise 'secondary smtp rejection'
      end
    end.new

    NotificationEmailJob.new.perform(notification.id)
    copy_job = AdditionalNotificationEmailDeliveryJob.jobs.last

    NotificationsMailer.stub(:additional_notification_copy, ->(_notification, _address) { failing_delivery }) do
      assert_raises(RuntimeError) do
        AdditionalNotificationEmailDeliveryJob.new.perform(*copy_job['args'])
      end
    end

    assert_equal [user.email], ActionMailer::Base.deliveries.last.to
    assert_equal 1,
                 user.additional_notification_email_audits.where(event: 'notification_copy_failed').count
  end

  def test_audit_store_failure_does_not_retry_an_accepted_optional_copy
    user = FactoryBot.create(:user)
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(:notification, user: user, event: 'general')
    NotificationEmailJob.new.perform(notification.id)
    copy_job = AdditionalNotificationEmailDeliveryJob.jobs.last

    AdditionalNotificationEmailService.stub(:audit!, ->(*) { raise 'audit unavailable' }) do
      assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
        AdditionalNotificationEmailDeliveryJob.new.perform(*copy_job['args'])
      end
    end
  end

  def test_queue_and_audit_failure_do_not_retry_an_accepted_primary_message
    user = FactoryBot.create(:user)
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(:notification, user: user, event: 'general')

    AdditionalNotificationEmailDeliveryJob.stub(:perform_async, ->(*) { raise 'queue unavailable' }) do
      AdditionalNotificationEmailService.stub(:audit!, ->(*) { raise 'audit unavailable' }) do
        assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
          NotificationEmailJob.new.perform(notification.id)
        end
      end
    end
  end

  def test_category_opt_out_suppresses_both_destinations
    user = FactoryBot.create(:user, receive_feedback_notifications: true)
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(
      :notification,
      :feedback,
      user: user,
      event: 'task_comment_created'
    )
    user.update!(receive_feedback_notifications: false)

    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      NotificationEmailJob.new.perform(notification.id)
    end
    assert_empty AdditionalNotificationEmailDeliveryJob.jobs
  end

  def test_category_opt_out_after_primary_delivery_suppresses_the_optional_copy
    user = FactoryBot.create(:user, receive_feedback_notifications: true)
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'secondary@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(
      :notification,
      :feedback,
      user: user,
      event: 'task_comment_created'
    )

    NotificationEmailJob.new.perform(notification.id)
    copy_job = AdditionalNotificationEmailDeliveryJob.jobs.last
    user.update!(receive_feedback_notifications: false)

    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      AdditionalNotificationEmailDeliveryJob.new.perform(*copy_job['args'])
    end
  end

  def test_an_optional_address_lookup_failure_does_not_retry_the_primary_message
    user = FactoryBot.create(:user)
    notification = FactoryBot.create(:notification, user: user, event: 'general')
    failing_lookup = -> { raise ActiveRecord::ConnectionNotEstablished, 'database unavailable' }

    user.stub(:additional_notification_email, failing_lookup) do
      notification.stub(:user, user) do
        Notification.stub(:find, notification) do
          assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
            NotificationEmailJob.new.perform(notification.id)
          end
        end
      end
    end

    assert_empty AdditionalNotificationEmailDeliveryJob.jobs
    assert_equal 1, user.additional_notification_email_audits.where(event: 'notification_copy_failed').count
  end

  def test_a_rejected_copy_is_retried_without_the_address_in_the_error
    user = FactoryBot.create(:user)
    additional = AdditionalNotificationEmailService.request(user: user, email: 'secondary@example.org')
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(:notification, user: user, event: 'general')
    NotificationEmailJob.new.perform(notification.id)
    copy_job = AdditionalNotificationEmailDeliveryJob.jobs.last
    smtp_rejection = Class.new do
      def deliver_now
        raise '550 5.1.1 <secondary@example.org>: Recipient address rejected'
      end
    end.new

    error = NotificationsMailer.stub(:additional_notification_copy, ->(_notification, _address) { smtp_rejection }) do
      assert_raises(AdditionalNotificationEmailService::DeliveryFailed) do
        AdditionalNotificationEmailDeliveryJob.new.perform(*copy_job['args'])
      end
    end

    assert_not_includes error.message, 'secondary@example.org'
    assert_nil error.cause
  end

  def test_a_copy_for_a_removed_address_is_dropped_without_a_failure_audit
    user = FactoryBot.create(:user)
    additional = AdditionalNotificationEmailService.request(user: user, email: 'secondary@example.org')
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    notification = FactoryBot.create(:notification, user: user, event: 'general')
    NotificationEmailJob.new.perform(notification.id)
    copy_job = AdditionalNotificationEmailDeliveryJob.jobs.last

    AdditionalNotificationEmailService.remove(user: user)

    assert_no_difference -> { ActionMailer::Base.deliveries.count } do
      AdditionalNotificationEmailDeliveryJob.new.perform(*copy_job['args'])
    end
    assert_equal 0, user.additional_notification_email_audits.where(event: 'notification_copy_failed').count
  end

  def test_runtime_duplicate_suppression_prevents_two_messages
    user = FactoryBot.create(:user, email: 'same@example.edu')
    additional = AdditionalNotificationEmailService.request(
      user: user,
      email: 'different@example.org'
    )
    AdditionalNotificationEmailService.verify(token: additional.verification_token)
    # Simulate a legacy duplicate that predates the validation guard.
    additional.update_column(:email, 'SAME@example.edu') # rubocop:disable Rails/SkipsModelValidations
    notification = FactoryBot.create(:notification, user: user, event: 'general')

    assert_difference -> { ActionMailer::Base.deliveries.count }, 1 do
      NotificationEmailJob.new.perform(notification.id)
    end
    assert_empty AdditionalNotificationEmailDeliveryJob.jobs
  end
end
