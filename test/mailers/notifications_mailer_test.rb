require 'test_helper'

# EN-T04: every event's mailer templates render without raising, in both
# HTML and text.
#
# NOTE FOR FUTURE CONTRIBUTORS: this file does not discover events
# automatically. When you add a new event, add its name and notification
# type to the EVENTS hash below. A missing entry here means a broken or
# missing template for that event falls back silently to
# single_notification and nothing catches it.
class NotificationsMailerTest < ActionMailer::TestCase
  # event => notification_type, matching the six events currently wired up
  # in NotificationService.notify call sites across the app.
  EVENTS = {
    'task_comment_created' => 'feedback',
    'extension_assessed' => 'extension',
    'group_membership_changed' => 'general',
    'new_task_available' => 'task',
    'task_due_date_changed' => 'task',
    'task_status_changed' => 'task'
  }.freeze

  LINK = '/projects/1/dashboard/A1'.freeze

  EVENTS.each do |event, notification_type|
    define_method("test_#{event}_renders_html_and_text") do
      # The mailer falls back to the generic template when an event-specific
      # template is missing, so require both event-specific template files.
      %w[html text].each do |format|
        template_path = Rails.root.join(
          'app',
          'views',
          'notifications_mailer',
          "#{event}.#{format}.erb"
        )

        assert template_path.file?,
               "#{event}: missing event-specific #{format} template"
      end

      notification = FactoryBot.create(
        :notification,
        notification_type: notification_type,
        event: event,
        message: "A realistic message for #{event}, long enough to catch interpolation errors.",
        link: LINK
      )

      mail = NotificationsMailer.single_notification(notification)

      assert mail.html_part.body.to_s.present?, "#{event}: HTML part did not render"
      assert mail.text_part.body.to_s.present?, "#{event}: text part did not render"
    end

    define_method("test_#{event}_subject_is_not_blank") do
      notification = FactoryBot.create(:notification, notification_type: notification_type, event: event)

      mail = NotificationsMailer.single_notification(notification)

      assert mail.subject.present?, "#{event}: subject was blank"

      # Every event shares one subject today, built at
      # app/mailers/notifications_mailer.rb:22. This assertion needs to
      # change if anyone adds a per-event subject lookup.
      expected_subject = "#{Doubtfire::Application.config.institution[:product_name]}: New notification"
      assert_equal expected_subject, mail.subject, "#{event}: subject shape changed"
    end

    define_method("test_#{event}_link_is_in_the_body") do
      notification = FactoryBot.create(
        :notification,
        notification_type: notification_type,
        event: event,
        link: LINK
      )

      mail = NotificationsMailer.single_notification(notification)
      expected_url = "#{Doubtfire::Application.config.institution[:host]}#{LINK}"

      assert_includes mail.html_part.body.to_s, expected_url, "#{event}: exact link missing from HTML body"
      assert_includes mail.text_part.body.to_s, expected_url, "#{event}: exact link missing from text body"
    end
  end

  def test_configured_sender_is_used
    institution = Doubtfire::Application.config.institution
    previous_sender = institution[:email_sender]
    institution[:email_sender] = 'notifications@example.edu'

    notification = FactoryBot.create(
      :notification,
      notification_type: 'feedback',
      event: 'task_comment_created'
    )

    mail = NotificationsMailer.single_notification(notification)

    assert_equal ['notifications@example.edu'], mail.from
  ensure
    institution[:email_sender] = previous_sender
  end
end
