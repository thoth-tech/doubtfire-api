require 'test_helper'

# A student's new portfolio submission tells the staff who will mark it.
class NotificationPortfolioSubmittedTest < ActiveSupport::TestCase
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
    @unit = @project.unit
    @student = @project.student

    @project.tutorial_enrolments.destroy_all
    tutor_role = @unit.employ_staff(FactoryBot.create(:user, :tutor), Role.tutor)
    @project.enrol_in(FactoryBot.create(:tutorial, unit: @unit, campus: @project.campus, unit_role: tutor_role))
    @tutor = tutor_role.user
    @project.reload
  end

  def submit_portfolio(as: @student, value: true)
    add_auth_header_for(user: as)
    put_json("/api/projects/#{@project.id}", id: @project.id, compile_portfolio: value)

    assert_equal 200, last_response.status, last_response.body
  end

  def staff_notifications
    Notification.where(event: 'portfolio_submitted')
  end

  def test_the_students_tutor_is_told_once
    assert_difference -> { staff_notifications.count }, 1 do
      submit_portfolio
    end

    notification = staff_notifications.first

    assert_equal @tutor, notification.user
    assert_equal 'portfolio', notification.notification_type
    assert_equal "#{@student.name} submitted a portfolio in #{@unit.code}.", notification.message
    assert_equal "/projects/#{@project.id}/dashboard", notification.link
    assert_equal @project, notification.notifiable
    assert_equal @student.id, notification.target_ids[:student_id]
    assert_equal @unit.id, notification.target_ids[:unit_id]

    assert_valid_push_payload(
      notification,
      expected_link: "/projects/#{@project.id}/dashboard",
      expected_body: 'A student submitted a portfolio.'
    )
  end

  def test_the_student_still_gets_their_own_receipt
    assert_difference -> { Notification.where(user: @student, event: 'portfolio_received').count }, 1 do
      submit_portfolio
    end
  end

  def test_a_student_with_no_tutor_tells_the_main_convenor
    @project.tutorial_enrolments.destroy_all
    @project.reload

    submit_portfolio

    assert_equal [@unit.main_convenor_user], staff_notifications.map(&:user)
  end

  def test_the_tutors_portfolio_preference_switches_it_off
    @tutor.update!(receive_portfolio_notifications: false)

    assert_no_difference -> { staff_notifications.count } do
      submit_portfolio
    end
  end

  def test_repeating_the_same_submission_does_not_tell_the_tutor_again
    submit_portfolio

    assert_no_difference -> { staff_notifications.count } do
      submit_portfolio
    end
  end

  def test_staff_submitting_on_the_students_behalf_are_not_told_about_their_own_action
    assert_no_difference -> { staff_notifications.where(user: @tutor).count } do
      submit_portfolio(as: @tutor)
    end
  end

  def test_one_email_for_the_tutor
    submit_portfolio
    NotificationEmailJob.drain

    tutor_mail = ActionMailer::Base.deliveries.select { |mail| mail.to.include?(@tutor.email) }
    staff_url = "/units/#{@unit.id}/students/portfolios/#{@project.id}"

    assert_equal 1, tutor_mail.count
    [tutor_mail.first.html_part.body.decoded, tutor_mail.first.text_part.body.decoded].each do |body|
      assert_includes body, "Hi #{@tutor.first_name}"
      assert_includes body, "#{@student.name} submitted a portfolio"
      assert_includes body, staff_url
      assert_includes body, '/edit_profile'
    end
    assert_includes tutor_mail.first.html_part.body.decoded, 'Portfolio submitted'
  end
end
