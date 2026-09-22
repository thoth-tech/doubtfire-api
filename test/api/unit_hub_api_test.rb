# frozen_string_literal: true

require 'test_helper'

class UnitHubApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper

  def app
    Rails.application
  end

  setup do
    @student = FactoryBot.create(:user, :student)
    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0, code: 'SIT111')
    @other_unit = FactoryBot.create(:unit, with_students: false, task_count: 0, code: 'SIT102')
    @project = @unit.enrol_student(@student, @unit.tutorials.first.campus)
    @staff = @unit.unit_roles.where(role: Role.convenor).first.user
    @announcement = @unit.unit_announcements.create!(title: 'Study update', body: 'Bring your questions.', published_at: 1.hour.ago)
    @session = @unit.unit_learning_sessions.create!(title: 'HelpHub', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour,
                                                    published: true, join_url: 'https://teams.microsoft.com/l/meetup-join/example')
  end

  def test_feed_contains_only_enrolled_unit_published_unexpired_content
    @other_unit.unit_announcements.create!(title: 'Other unit secret', body: 'Other students only.', published_at: 1.hour.ago)
    @other_unit.unit_learning_sessions.create!(title: 'Other class', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour, published: true)
    @unit.unit_announcements.create!(title: 'Draft', body: 'Draft body')
    @unit.unit_announcements.create!(title: 'Expired', body: 'Old body', published_at: 2.days.ago, expires_at: 1.day.ago)
    @unit.unit_announcements.create!(title: 'Scheduled', body: 'Future body', published_at: 1.day.from_now)
    @unit.unit_learning_sessions.create!(title: 'Draft class', start_at: 1.day.from_now, end_at: 1.day.from_now + 1.hour)
    add_auth_header_for(user: @student)
    get '/api/unit_hub'

    assert_equal 200, last_response.status, last_response.body
    body = JSON.parse(last_response.body)
    assert_equal [@unit.id], body['units'].map { |unit| unit['id'] }
    assert_equal [false], body['units'].map { |unit| unit['can_manage'] }
    assert_equal [@announcement.id], body['announcements'].map { |row| row['id'] }
    assert_equal [@session.id], body['sessions'].map { |row| row['id'] }
    assert_equal 'private, no-store', last_response.headers['cache-control']
  end

  def test_withdrawal_and_inactive_units_are_removed_on_next_request
    add_auth_header_for(user: @student)
    @project.update!(enrolled: false)
    get '/api/unit_hub'
    assert_equal [], JSON.parse(last_response.body)['units']
    assert_equal [], JSON.parse(last_response.body)['announcements']
    assert_equal [], JSON.parse(last_response.body)['sessions']

    @project.update!(enrolled: true)
    @unit.update!(active: false)
    get '/api/unit_hub'
    assert_equal [], JSON.parse(last_response.body)['units']
  end

  def test_global_staff_role_does_not_grant_unassigned_unit_access
    add_auth_header_for(user: FactoryBot.create(:user, :convenor))
    get '/api/unit_hub'
    assert_equal [], JSON.parse(last_response.body)['units']
    get "/api/units/#{@unit.id}/announcements"
    assert_equal 404, last_response.status
  end

  def test_student_cannot_manage_even_their_own_unit
    add_auth_header_for(user: @student)
    get "/api/units/#{@unit.id}/announcements"
    assert_equal 403, last_response.status, last_response.body
    assert_no_difference 'UnitAnnouncement.count' do
      post "/api/units/#{@unit.id}/announcements", announcement: { title: 'Injected', body: 'No' }
    end
    assert_equal 403, last_response.status
    put "/api/units/#{@unit.id}/sessions/#{@session.id}", session: { title: 'Changed' }
    assert_equal 403, last_response.status
    delete "/api/units/#{@unit.id}/announcements/#{@announcement.id}"
    assert_equal 403, last_response.status
  end

  def test_assigned_staff_can_create_edit_list_drafts_and_remove_content
    add_auth_header_for(user: @staff)
    post "/api/units/#{@unit.id}/announcements", announcement: { title: 'New draft', body: 'Staff note', unit_id: @other_unit.id }
    assert_equal 201, last_response.status, last_response.body
    id = JSON.parse(last_response.body)['id']
    assert_equal @unit.id, UnitAnnouncement.find(id).unit_id
    assert_equal @staff.id, UnitAnnouncement.find(id).author_id

    put "/api/units/#{@unit.id}/announcements/#{id}", announcement: { published_at: Time.current.iso8601 }
    assert_equal 200, last_response.status, last_response.body
    get "/api/units/#{@unit.id}/announcements"
    assert_includes JSON.parse(last_response.body).map { |row| row['id'] }, id
    delete "/api/units/#{@unit.id}/announcements/#{id}"
    assert_equal 200, last_response.status
    assert_not UnitAnnouncement.exists?(id)
  end

  def test_staff_can_create_weekly_draft_then_publish_and_edit_a_session
    add_auth_header_for(user: @staff)
    start_at = 2.days.from_now.in_time_zone('Australia/Melbourne').change(hour: 17, min: 0, sec: 0)
    post "/api/units/#{@unit.id}/sessions", session: {
      title: 'Weekly lecture', kind: 'lecture', start_at: start_at.iso8601,
      end_at: (start_at + 1.hour).iso8601, timezone: 'Australia/Melbourne',
      recurrence: 'weekly', recurrence_until: (start_at.to_date + 2.weeks).iso8601,
      join_url: 'https://teams.microsoft.com/l/meetup-join/example'
    }
    assert_equal 201, last_response.status, last_response.body
    row = JSON.parse(last_response.body)
    assert_equal false, row['published']
    id = row['id']
    get "/api/units/#{@unit.id}/sessions"
    assert_includes JSON.parse(last_response.body).map { |record| record['id'] }, id
    put "/api/units/#{@unit.id}/sessions/#{id}", session: { published: true, title: 'Lecture and questions' }
    assert_equal 200, last_response.status, last_response.body
    add_auth_header_for(user: @student)
    get '/api/unit_hub'
    occurrences = JSON.parse(last_response.body)['sessions'].select { |record| record['id'] == id }
    assert_equal 3, occurrences.length
    assert_equal ['Lecture and questions'], occurrences.map { |record| record['title'] }.uniq
  end

  def test_cross_unit_record_ids_cannot_be_modified_or_deleted
    add_auth_header_for(user: @staff)
    other = @other_unit.unit_announcements.create!(title: 'Private', body: 'Protected')
    put "/api/units/#{@unit.id}/announcements/#{other.id}", announcement: { title: 'Changed' }
    assert_equal 404, last_response.status
    delete "/api/units/#{@unit.id}/announcements/#{other.id}"
    assert_equal 404, last_response.status
    assert_equal 'Private', other.reload.title
    post "/api/units/#{@other_unit.id}/sessions", session: { title: 'No' }
    assert_equal 404, last_response.status
  end

  def test_observer_staff_cannot_publish
    observer = FactoryBot.create(:user, :tutor)
    @unit.unit_roles.create!(user: observer, role: Role.tutor, observer_only: true)
    add_auth_header_for(user: observer)
    get '/api/unit_hub'
    assert_equal false, JSON.parse(last_response.body)['units'].first['can_manage']
    post "/api/units/#{@unit.id}/announcements", announcement: { title: 'No', body: 'No' }
    assert_equal 403, last_response.status
  end

  def test_session_cancellation_retains_identity_but_hides_join_link
    add_auth_header_for(user: @staff)
    delete "/api/units/#{@unit.id}/sessions/#{@session.id}"
    assert_equal 200, last_response.status
    assert @session.reload.cancelled?
    add_auth_header_for(user: @student)
    get '/api/unit_hub'
    row = JSON.parse(last_response.body)['sessions'].first
    assert row['cancelled']
    assert_nil row['join_url']
    assert_equal "#{@session.id}-0", row['occurrence_id']
  end

  def test_invalid_links_offsets_and_schedules_are_rejected
    add_auth_header_for(user: @staff)
    %w[javascript:alert(1) http://example.com https://user:password@example.com].each do |url|
      put "/api/units/#{@unit.id}/sessions/#{@session.id}", session: { join_url: url }
      assert_equal 400, last_response.status, last_response.body
    end
    put "/api/units/#{@unit.id}/sessions/#{@session.id}", session: { start_at: '2026-10-01T17:00:00' }
    assert_equal 400, last_response.status
    put "/api/units/#{@unit.id}/sessions/#{@session.id}", session: { start_at: '2026-10-01T17:00:00', end_at: '2026-10-01T18:00:00' }
    assert_equal 400, last_response.status, last_response.body
    put "/api/units/#{@unit.id}/announcements/#{@announcement.id}", announcement: { published_at: 'not a date' }
    assert_equal 400, last_response.status, last_response.body
    put "/api/units/#{@unit.id}/sessions/#{@session.id}", session: { timezone: 'Bad/Zone' }
    assert_equal 400, last_response.status
    put "/api/units/#{@unit.id}/sessions/#{@session.id}", session: { end_at: 1.day.ago.iso8601 }
    assert_equal 400, last_response.status
  end

  def test_calendar_learning_sessions_preference_is_saved_only_for_current_user
    other = FactoryBot.create(:user, :student)
    other_cal = Webcal.create!(user: other, guid: SecureRandom.uuid)
    add_auth_header_for(user: @student)
    put '/api/webcal', webcal: { enabled: true, include_learning_sessions: true }
    assert_equal 200, last_response.status, last_response.body
    assert_equal true, JSON.parse(last_response.body)['include_learning_sessions']
    get '/api/webcal'
    assert_equal true, JSON.parse(last_response.body)['include_learning_sessions']
    assert_not other_cal.reload.include_learning_sessions?
    put '/api/webcal', webcal: { include_learning_sessions: false }
    assert_equal false, JSON.parse(last_response.body)['include_learning_sessions']
  end

  def test_authentication_required_for_feed_and_writes
    get '/api/unit_hub'
    assert_equal 419, last_response.status
    post "/api/units/#{@unit.id}/announcements", announcement: { title: 'No', body: 'No' }
    assert_equal 419, last_response.status
  end
end
