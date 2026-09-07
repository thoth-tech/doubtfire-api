require 'test_helper'
require 'minitest/mock'

# EN-V07: a newly accepted manual portfolio submission sends one receipt to
# the submitting student.
class NotificationPortfolioTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::PushNotificationHelper

  def app
    Rails.application
  end

  setup do
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    @project = FactoryBot.create(:project)
    @project.campus.update!(timezone: 'Australia/Melbourne')
    @student = @project.student

    add_auth_header_for(user: @student)
  end

  def submit_portfolio(value: true)
    # Some receipt assertions freeze time. Mint the request token inside that
    # clock so the authentication expiry is evaluated against the same instant.
    add_auth_header_for(user: @student)

    put_json(
      "/api/projects/#{@project.id}",
      id: @project.id,
      compile_portfolio: value
    )

    assert_equal 200, last_response.status, last_response.body

    # Email is queued rather than sent inline since EN-F03. Draining here keeps
    # every deliveries assertion in this file reading the way it did before,
    # and it is the same shape as run_job in the other notification tests.
    NotificationEmailJob.drain
  end

  def delivered_body
    mail = ActionMailer::Base.deliveries.last
    return '' if mail.nil?

    mail.multipart? ? mail.parts.map { |part| part.body.decoded }.join("\n") : mail.body.decoded
  end

  def test_a_new_portfolio_submission_sends_one_receipt_to_the_student
    travel_to Time.zone.parse('2026-08-23 12:34:00 UTC') do
      assert_difference 'Notification.count', 1 do
        submit_portfolio
      end
    end
    NotificationEmailJob.drain

    notification = Notification.find_by!(user: @student, event: 'portfolio_received')

    assert_equal @student, notification.user
    assert_equal 'portfolio', notification.notification_type
    assert_equal 'portfolio_received', notification.event
    assert_equal(
      "#{Doubtfire::Application.config.institution[:product_name]} received your " \
      'portfolio submission at 23 August 2026 at 10:34 PM AEST (UTC+10:00).',
      notification.message
    )
    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard",
      expected_body: 'Your portfolio submission was received.'
    )

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_equal [@student.email], ActionMailer::Base.deliveries.last.to
    assert_equal(
      "#{Doubtfire::Application.config.institution[:product_name]}: New notification",
      ActionMailer::Base.deliveries.last.subject
    )
  end

  def test_the_receipt_uses_the_event_template_and_excludes_assessment_content
    assessment_content = 'PRIVATE-ASSESSMENT-RATIONALE-7429'
    @project.update!(grade_rationale: assessment_content, submitted_grade: 3)

    travel_to Time.zone.parse('2026-08-23 12:34:00 UTC') do
      submit_portfolio
    end
    NotificationEmailJob.drain

    body = delivered_body

    assert_not_empty body, 'guard: the body must be readable or the privacy assertions prove nothing'
    assert_includes body, '23 August 2026 at 10:34 PM AEST (UTC+10:00)'
    assert_includes body, 'This receipt confirms when the submission was received'
    assert_includes body, 'It does not confirm an assessment outcome'
    assert_not_includes body, assessment_content
  end

  def test_portfolio_preference_suppresses_every_notification_channel
    @student.update!(receive_portfolio_notifications: false)

    assert_no_difference 'Notification.count' do
      submit_portfolio
    end

    assert_empty ActionMailer::Base.deliveries
    assert @project.reload.compile_portfolio?
    assert_not_nil @project.portfolio_submission_date
  end

  def test_retrying_a_pending_manual_submission_does_not_send_a_second_receipt
    travel_to Time.zone.parse('2026-08-23 12:34:00 UTC') do
      submit_portfolio
    end

    original_submission_date = @project.reload.portfolio_submission_date
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    travel_to Time.zone.parse('2026-08-23 12:39:00 UTC') do
      assert_no_difference 'Notification.count' do
        submit_portfolio
      end
    end

    assert_empty ActionMailer::Base.deliveries
    assert_equal original_submission_date, @project.reload.portfolio_submission_date
  end

  def test_a_later_resubmission_receives_a_new_receipt
    travel_to Time.zone.parse('2026-08-23 12:34:00 UTC') do
      submit_portfolio
    end
    NotificationEmailJob.drain

    first_submission_date = @project.reload.portfolio_submission_date
    @project.update!(compile_portfolio: false)
    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.clear

    travel_to Time.zone.parse('2026-08-24 01:15:00 UTC') do
      assert_difference 'Notification.count', 1 do
        submit_portfolio
      end
    end
    NotificationEmailJob.drain

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_operator @project.reload.portfolio_submission_date, :>, first_submission_date
  end

  def test_a_manual_submission_replaces_a_pending_auto_generated_portfolio
    @project.update!(
      compile_portfolio: true,
      portfolio_auto_generated: true,
      portfolio_submission_date: nil
    )

    assert_difference 'Notification.count', 1 do
      submit_portfolio
    end
    NotificationEmailJob.drain

    assert_equal 1, ActionMailer::Base.deliveries.count
    assert_not @project.reload.portfolio_auto_generated?
    assert_not_nil @project.portfolio_submission_date
  end

  def test_cancelling_portfolio_generation_does_not_send_a_receipt
    assert_no_difference 'Notification.count' do
      submit_portfolio(value: false)
    end

    assert_empty ActionMailer::Base.deliveries
    assert_nil @project.reload.portfolio_submission_date
  end

  def test_a_notification_failure_does_not_reject_the_submission
    NotificationService.stub :notify, ->(**_kwargs) { raise StandardError, 'notification failed' } do
      assert_nothing_raised do
        submit_portfolio
      end
    end

    assert @project.reload.compile_portfolio?
    assert_not_nil @project.portfolio_submission_date
  end
end
