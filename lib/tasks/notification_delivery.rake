# frozen_string_literal: true

namespace :notifications do
  desc 'Count persisted email delivery outcomes without exposing recipient data'
  task delivery_counts: :environment do
    puts Notification.group(:email_delivery_state).count.to_json
  end

  desc 'Requeue one investigated failed email: NOTIFICATION_ID=123'
  task retry_email: :environment do
    notification = Notification.find(Integer(ENV.fetch('NOTIFICATION_ID'), 10))
    notification.with_lock do
      abort 'Only failed or queue_failed emails can be retried' unless %w[failed queue_failed].include?(notification.email_delivery_state)

      notification.update!(email_delivery_state: 'pending', email_delivery_error_class: nil)
    end
    NotificationService.queue_email(notification)
    puts({ notification_id: notification.id, email_delivery_state: notification.reload.email_delivery_state }.to_json)
  end
end
