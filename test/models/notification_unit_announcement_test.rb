# frozen_string_literal: true

require 'test_helper'

# Unit Hub announcements tell the unit's students and staff when one is
# published, pinned or meaningfully changed.
class NotificationUnitAnnouncementTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::PushNotificationHelper

  PUBLISHED = 'unit_announcement_published'
  UPDATED = 'unit_announcement_updated'

  def app
    Rails.application
  end

  # The fan-out jobs carry until_executed locks. Sidekiq's fake mode never runs
  # a job a test clears, so a lock taken on push would outlive the test and turn
  # the same job away in the next one. Idempotency here comes from the dedupe
  # keys, which these tests check, so the locks are switched off.
  teardown do
    SidekiqUniqueJobs.config.enabled = @unique_jobs_enabled
  end

  setup do
    @unique_jobs_enabled = SidekiqUniqueJobs.config.enabled
    SidekiqUniqueJobs.config.enabled = false
    ActionMailer::Base.deliveries.clear
    Sidekiq::Worker.clear_all

    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0, code: 'SIT222')
    @campus = @unit.tutorials.first.campus
    @convenor = @unit.unit_roles.where(role: Role.convenor).first.user
    @tutor = FactoryBot.create(:user, :tutor)
    @unit.employ_staff(@tutor, Role.tutor)

    @student = FactoryBot.create(:user, :student)
    @unit.enrol_student(@student, @campus)
    @withdrawn = FactoryBot.create(:user, :student)
    @unit.enrol_student(@withdrawn, @campus).update!(enrolled: false)

    # The unit factory also staffs the unit's tutorial, so ask for its staff.
    staff_ids = @unit.unit_roles.where(role: [Role.tutor, Role.convenor]).pluck(:user_id)
    @recipient_ids = (staff_ids - [@tutor.id] + [@student.id]).uniq.sort

    @other_unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    @outsider = FactoryBot.create(:user, :student)
    @other_unit.enrol_student(@outsider, @other_unit.tutorials.first.campus)
  end

  def announce(**attributes)
    defaults = { title: 'Week 3 lab', body: 'Bring your laptop to the lab.', published_at: 1.minute.ago, author: @tutor }
    @unit.unit_announcements.create!(defaults.merge(attributes))
  end

  def run_jobs
    UnitAnnouncementNotificationJob.drain
  end

  def notified(event = PUBLISHED)
    Notification.where(event: event)
  end

  def test_new_users_get_the_in_app_channel_only
    user = FactoryBot.create(:user, :student)

    assert user.receive_unit_hub_notifications
    assert_not user.receive_unit_hub_email_notifications
    assert_not user.receive_unit_hub_push_notifications
    assert_not user.receive_unit_hub_session_reminders
  end

  def test_publishing_tells_enrolled_students_and_staff_but_not_the_author
    add_auth_header_for(user: @tutor)
    post_json "/api/units/#{@unit.id}/announcements", announcement: { title: 'Week 3 lab', body: 'Bring a laptop.', published_at: 1.minute.ago.iso8601 }
    assert_equal 201, last_response.status, last_response.body

    run_jobs

    assert_equal @recipient_ids, notified.pluck(:user_id).sort
    notification = notified.find_by(user: @student)
    announcement = UnitAnnouncement.last

    assert_equal 'unit_hub', notification.notification_type
    assert_equal 'New announcement in SIT222: Week 3 lab', notification.message
    assert_equal "/unit-hub?unit=#{@unit.id}&announcement=#{announcement.id}", notification.link
    assert_equal announcement, notification.notifiable
    assert_equal @unit.id, notification.target_ids[:unit_id]
    assert_equal announcement.id, notification.target_ids[:announcement_id]
    assert_nil notification.target_ids[:session_id]
    assert_nil notification.target_ids[:project_id]
    assert_equal notification.link, notification.web_path
  end

  def test_the_unit_hub_category_switch_leaves_a_user_out
    @student.update!(receive_unit_hub_notifications: false)
    announce
    run_jobs

    assert_not notified.exists?(user: @student)
    assert notified.exists?(user: @convenor)
  end

  def test_a_scheduled_announcement_waits_for_its_publication_time
    announcement = announce(published_at: 2.hours.from_now)

    job = UnitAnnouncementNotificationJob.jobs.last
    assert_in_delta announcement.published_at.to_f, job['at'], 1
    UnitAnnouncementNotificationJob.clear

    # Run early, as though the clock were wrong, and nothing is sent.
    UnitAnnouncementNotificationJob.new.perform(announcement.id, PUBLISHED, "published-#{announcement.published_at.to_i}")
    assert_equal 0, notified.count

    travel_to(announcement.published_at + 1.minute) do
      UnitAnnouncementNotificationJob.new.perform(announcement.id, PUBLISHED, "published-#{announcement.published_at.to_i}")
    end
    assert_equal @recipient_ids.length, notified.count
  end

  def test_a_rescheduled_publication_ignores_the_old_job
    announcement = announce(published_at: 2.hours.from_now)
    old_version = "published-#{announcement.published_at.to_i}"
    announcement.update!(published_at: 1.minute.ago)

    UnitAnnouncementNotificationJob.new.perform(announcement.id, PUBLISHED, old_version)
    assert_equal 0, notified.count

    run_jobs
    assert_equal @recipient_ids.length, notified.count
  end

  def test_drafts_expired_and_backfilled_announcements_are_not_news
    announce(published_at: nil)
    announce(published_at: 3.days.ago, expires_at: 1.day.ago)
    announce(published_at: 2.months.ago)
    run_jobs

    assert_equal 0, notified.count
  end

  def test_publishing_a_draft_later_tells_the_unit
    announcement = announce(published_at: nil)
    run_jobs
    announcement.update!(published_at: Time.current)
    run_jobs

    assert_equal @recipient_ids.length, notified.count
  end

  def test_a_retried_or_repeated_job_sends_nothing_twice
    announcement = announce
    job_args = UnitAnnouncementNotificationJob.jobs.last['args']
    run_jobs

    assert_no_difference -> { Notification.count } do
      UnitAnnouncementNotificationJob.new.perform(*job_args)
      announcement.update!(expires_at: 1.week.from_now)
      run_jobs
    end
  end

  def test_pinning_republishes_and_unpinning_does_not
    announcement = announce
    run_jobs

    announcement.update!(pinned: true)
    run_jobs
    pinned = notified.where(user: @student).order(:id).last
    assert_equal 2, notified.where(user: @student).count
    assert_equal 'Pinned announcement in SIT222: Week 3 lab', pinned.message

    announcement.update!(pinned: false)
    run_jobs
    assert_equal 2, notified.where(user: @student).count
    assert_equal 0, notified(UPDATED).count
  end

  def test_a_meaningful_edit_tells_the_unit_after_the_debounce_window
    announcement = travel_to(2.hours.ago) { announce.tap { run_jobs } }
    run_jobs

    announcement.update!(body: 'The lab has moved to the library this week.')
    run_jobs

    assert_equal @recipient_ids, notified(UPDATED).pluck(:user_id).sort
    assert_equal 'Announcement updated in SIT222: Week 3 lab', notified(UPDATED).first.message
  end

  def test_a_typo_fix_is_not_an_update
    announcement = travel_to(2.hours.ago) { announce(body: 'Bring your labtop to the lab.').tap { run_jobs } }
    run_jobs

    announcement.update!(body: 'Bring your laptop to the lab!')
    announcement.update!(title: 'week 3 lab')
    run_jobs

    assert_equal 0, notified(UPDATED).count
  end

  def test_updates_are_debounced_to_one_per_announcement_per_recipient_every_30_minutes
    announcement = travel_to(2.hours.ago) { announce.tap { run_jobs } }
    run_jobs

    announcement.update!(body: 'The lab has moved to the library this week.')
    run_jobs
    announcement.update!(body: 'The lab is back in the usual room, sorry for the noise.')
    run_jobs
    assert_equal 1, notified(UPDATED).where(user: @student).count

    travel_to(31.minutes.from_now) do
      announcement.update!(body: 'The lab is cancelled this week because of the public holiday.')
      run_jobs
    end
    assert_equal 2, notified(UPDATED).where(user: @student).count
  end

  def test_an_edit_straight_after_publishing_is_held_back
    announcement = announce
    run_jobs
    announcement.update!(body: 'Something completely different to say about the lab.')
    run_jobs

    assert_equal 0, notified(UPDATED).count
  end

  def test_meaningful_edit_rules
    rules = UnitHub::Notifications

    assert_not rules.meaningful_edit?('Bring your laptop.', 'bring your  laptop!')
    assert_not rules.meaningful_edit?('Bring your labtop.', 'Bring your laptop.')
    assert_not rules.meaningful_edit?('Meet in the the lab.', 'Meet in the lab.')
    assert rules.meaningful_edit?('Lab in room 204.', 'Lab in room 205.')
    assert rules.meaningful_edit?('The lab is on.', 'The lab is not on.')
    assert rules.meaningful_edit?('Meet in the lab.', 'Meet in the library.')
    assert rules.meaningful_edit?('Lab on Monday.', 'Lab on Tuesday instead, sorry.')
  end

  def test_email_and_push_follow_their_own_opt_ins
    @student.update!(receive_unit_hub_email_notifications: true, receive_unit_hub_push_notifications: false)
    @convenor.update!(receive_unit_hub_email_notifications: false, receive_unit_hub_push_notifications: true)
    NotificationEmailJob.clear
    PushNotificationDeliveryJob.clear

    announce
    run_jobs

    student_notification = notified.find_by(user: @student)
    convenor_notification = notified.find_by(user: @convenor)
    email_ids = NotificationEmailJob.jobs.map { |job| job['args'].first }
    push_ids = PushNotificationDeliveryJob.jobs.map { |job| job['args'].first }

    assert_equal [student_notification.id], email_ids
    assert_equal [convenor_notification.id], push_ids
    assert NotificationService.deliver_to?(@student, 'unit_hub', channel: :email)
    assert_not NotificationService.deliver_to?(@student, 'unit_hub', channel: :push)

    # Switching the whole category off wins over a channel left on.
    @student.update!(receive_unit_hub_notifications: false)
    assert_not NotificationService.deliver_to?(@student, 'unit_hub', channel: :email)
  end

  def test_a_queued_email_or_push_checks_the_channel_again
    @student.update!(receive_unit_hub_email_notifications: true, receive_unit_hub_push_notifications: true)
    announce
    run_jobs
    notification = notified.find_by(user: @student)
    @student.update!(receive_unit_hub_email_notifications: false, receive_unit_hub_push_notifications: false)

    ActionMailer::Base.deliveries.clear
    NotificationEmailJob.new.perform(notification.id)
    assert_empty ActionMailer::Base.deliveries

    PushNotificationService.stub(:deliver, ->(_) { flunk 'push must not be sent' }) do
      PushNotificationDeliveryJob.new.perform(notification.id)
    end
  end

  def test_the_lock_screen_does_not_show_the_title
    announcement = announce(title: 'Exam results for Jordan Smith')
    run_jobs
    notification = notified.find_by(user: @student)

    assert_valid_push_payload(
      notification,
      expected_link: "/unit-hub?unit=#{@unit.id}&announcement=#{announcement.id}",
      expected_body: 'There is a new announcement in your unit.'
    )
    assert_not_includes PushNotificationService.payload_for(notification), 'Jordan'
  end

  def test_an_inactive_unit_tells_nobody
    @unit.update!(active: false)
    announce
    run_jobs

    assert_equal 0, notified.count
  end

  def test_a_deleted_announcement_leaves_ids_that_say_so
    announcement = announce
    run_jobs
    notification = notified.find_by(user: @student)
    announcement.destroy!

    ids = notification.reload.target_ids
    assert_nil ids[:announcement_id]
    assert_nil ids[:unit_id]
  end

  def test_the_email_uses_the_shared_layout_with_details_and_a_button
    @student.update!(receive_unit_hub_email_notifications: true)
    announcement = announce(body: 'Bring your laptop to the lab. ' * 20)
    run_jobs
    NotificationEmailJob.drain

    mail = ActionMailer::Base.deliveries.find { |delivery| delivery.to.include?(@student.email) }
    assert_not_nil mail
    html = mail.html_part.body.decoded
    text = mail.text_part.body.decoded
    url = "/unit-hub?unit=#{@unit.id}&amp;announcement=#{announcement.id}"

    assert_includes html, 'New announcement in SIT222'
    assert_includes html, 'Week 3 lab'
    assert_includes html, 'ot-details'
    assert_includes html, url
    assert_includes html, 'Read the announcement'
    assert_includes html, '/edit_profile'
    assert_includes text, "/unit-hub?unit=#{@unit.id}&announcement=#{announcement.id}"
    assert_includes text, '/edit_profile'
    assert_operator html.scan('Bring your laptop').length, :<, 20
  end

  def test_the_updated_email_renders
    @student.update!(receive_unit_hub_email_notifications: true)
    announcement = travel_to(2.hours.ago) { announce.tap { run_jobs } }
    run_jobs
    announcement.update!(body: 'The lab has moved to the library this week.')
    run_jobs
    NotificationEmailJob.drain

    mail = ActionMailer::Base.deliveries.select { |delivery| delivery.to.include?(@student.email) }.last
    assert_includes mail.html_part.body.decoded, 'Announcement updated in SIT222'
    assert_includes mail.text_part.body.decoded, 'The lab has moved to the library'
  end

  def test_the_preferences_can_be_saved_through_the_users_api
    add_auth_header_for(user: @student)
    put_json "/api/users/#{@student.id}", user: {
      receive_unit_hub_notifications: false,
      receive_unit_hub_email_notifications: true,
      receive_unit_hub_push_notifications: true,
      receive_unit_hub_session_reminders: true
    }
    assert_equal 200, last_response.status, last_response.body

    body = JSON.parse(last_response.body)
    assert_equal false, body['receive_unit_hub_notifications']
    assert body['receive_unit_hub_session_reminders']

    put_json "/api/users/#{@student.id}", user: { receive_unit_hub_notifications: nil, receive_unit_hub_email_notifications: nil }
    @student.reload
    assert @student.receive_unit_hub_notifications
    assert_not @student.receive_unit_hub_email_notifications
  end
end
