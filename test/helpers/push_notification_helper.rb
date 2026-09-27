# frozen_string_literal: true

module TestHelpers
  module PushNotificationHelper
    def parsed_push_notification(notification)
      JSON.parse(
        PushNotificationService.payload_for(notification)
      ).fetch('notification')
    end

    def assert_valid_push_payload(notification, expected_link:, expected_body: nil)
      push = parsed_push_notification(notification)
      data = push.fetch('data')
      expected_body ||= notification.message.to_s.truncate(
        PushNotificationService::MAX_BODY_LENGTH
      )

      assert push['title'].present?, 'push title must be present'
      assert_equal expected_body, push['body']
      assert_operator(
        push['body'].length,
        :<=,
        PushNotificationService::MAX_BODY_LENGTH
      )
      assert_equal notification.id, data['notification_id']
      assert_equal expected_link, data['link']
      assert data['link'].present?, 'push data.link must be present'

      push
    end
  end
end
