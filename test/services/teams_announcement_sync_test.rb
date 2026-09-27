# frozen_string_literal: true

require 'test_helper'

class TeamsAnnouncementSyncTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper

  TENANT = '11111111-1111-4111-8111-111111111111'
  CLIENT = '22222222-2222-4222-8222-222222222222'
  TEAM = '33333333-3333-4333-8333-333333333333'
  PUBLISHER = '44444444-4444-4444-8444-444444444444'
  CHANNEL = '19:approved-channel@thread.tacv2'

  def app
    Rails.application
  end

  setup do
    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    @student = FactoryBot.create(:user, :student)
    @project = @unit.enrol_student(@student, @unit.tutorials.first.campus)
    @now = Time.current.change(usec: 0)
    @mapping_hash = { unit_id: @unit.id, team_id: TEAM, channel_id: CHANNEL, publisher_ids: [PUBLISHER], student_visible: true }
    @env = { 'DF_TEAMS_ANNOUNCEMENTS_ENABLED' => 'true', 'DF_TEAMS_TENANT_ID' => TENANT,
             'DF_TEAMS_CLIENT_ID' => CLIENT, 'DF_TEAMS_CLIENT_SECRET' => 'unit-test-secret',
             'DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash].to_json }
    @path = "/v1.0/teams/#{TEAM}/channels/#{ERB::Util.url_encode(CHANNEL)}/messages"
    @list_url = "https://graph.microsoft.com#{@path}?$top=50"
    stub_request(:post, "https://login.microsoftonline.com/#{TENANT}/oauth2/v2.0/token")
      .to_return(body: { access_token: 'test-access-token', token_type: 'Bearer' }.to_json)
  end

  def teams_message(id = '12345', **changes)
    { 'id' => id, 'messageType' => 'message', 'replyToId' => nil,
      'from' => { 'user' => { 'id' => PUBLISHER } },
      'channelIdentity' => { 'teamId' => TEAM, 'channelId' => CHANNEL },
      'subject' => 'Weekly update', 'createdDateTime' => (@now - 1.hour).iso8601,
      'lastModifiedDateTime' => (@now - 1.hour).iso8601,
      'body' => { 'contentType' => 'html', 'content' => '<p>Bring &amp; discuss questions.</p><script>unsafe()</script>' },
      'webUrl' => "https://teams.microsoft.com/l/message/#{ERB::Util.url_encode(CHANNEL)}/#{id}?groupId=#{TEAM}&tenantId=#{TENANT}" }.merge(changes.transform_keys(&:to_s))
  end

  def feed(*messages)
    stub_request(:get, @list_url).to_return(body: { value: messages }.to_json)
  end

  def sync(now: @now, env: @env)
    UnitHub::Teams::AnnouncementSync.new(configuration: UnitHub::Teams::Configuration.new(env), now: now).call
  end

  def with_env(values = @env)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_import_is_plain_text_idempotent_and_owned_by_its_source
    manual = @unit.unit_announcements.create!(title: 'Manual', body: 'Keep this', published_at: @now)
    feed(teams_message)
    assert_equal 1, sync[:synced]
    record = @unit.unit_announcements.where(source_provider: 'microsoft_teams').sole
    assert_equal 'Weekly update', record.title
    assert_includes record.body, 'Bring & discuss questions.'
    assert_not_includes record.body, '<'
    assert_nil record.author_id
    assert_equal @now, record.source_imported_at
    assert_equal @now + 7.days, record.expires_at
    assert_no_difference('UnitAnnouncement.count') { sync }
    assert_equal 'Keep this', manual.reload.body
  end

  def test_edits_update_the_same_record_and_source_deletion_hides_it
    feed(teams_message)
    sync
    record = @unit.unit_announcements.sole
    feed(teams_message(subject: 'Changed notice', lastModifiedDateTime: @now.iso8601))
    sync(now: @now + 5.minutes)
    assert_equal 'Changed notice', record.reload.title
    assert_equal 1, @unit.unit_announcements.count
    feed(teams_message(deletedDateTime: @now.iso8601, from: nil))
    sync(now: @now + 10.minutes)
    assert_nil record.reload.published_at
  end

  def test_student_system_reply_application_and_wrong_channel_posts_are_not_imported
    feed(teams_message('1', from: { 'user' => { 'id' => CLIENT } }),
         teams_message('2', messageType: 'systemEventMessage'), teams_message('3', replyToId: '1'),
         teams_message('4', from: { 'application' => { 'id' => CLIENT } }),
         teams_message('5', channelIdentity: { 'teamId' => CLIENT, 'channelId' => CHANNEL }))
    assert_no_difference('UnitAnnouncement.count') { sync }
  end

  def test_source_link_must_match_the_mapped_tenant_team_channel_and_message
    feed(teams_message(webUrl: "https://teams.microsoft.com/l/message/#{ERB::Util.url_encode(CHANNEL)}/other?groupId=#{TEAM}&tenantId=#{TENANT}"))
    assert_no_difference('UnitAnnouncement.count') { sync }
    feed(teams_message(webUrl: 'https://evil.example/private'))
    assert_no_difference('UnitAnnouncement.count') { sync }
  end

  def test_old_message_omitted_from_recent_pages_is_rechecked_not_assumed_deleted
    feed(teams_message)
    sync
    record = @unit.unit_announcements.sole
    feed
    lookup = stub_request(:get, "https://graph.microsoft.com#{@path}/12345").to_return(body: teams_message(subject: 'Old edited notice', lastModifiedDateTime: @now.iso8601).to_json)
    sync(now: @now + 5.minutes)
    assert_requested lookup
    assert_equal 'Old edited notice', record.reload.title
    assert_not_nil record.published_at
    stub_request(:get, "https://graph.microsoft.com#{@path}/12345").to_return(status: 404)
    sync(now: @now + 10.minutes)
    assert_nil record.reload.published_at
  end

  def test_old_message_lookup_cannot_import_a_different_response_id
    feed(teams_message)
    sync
    feed
    stub_request(:get, "https://graph.microsoft.com#{@path}/12345").to_return(body: teams_message('999').to_json)
    assert_no_difference('UnitAnnouncement.count') { assert_equal 1, sync(now: @now + 5.minutes)[:failed] }
    assert_equal 'failed', TeamsAnnouncementSyncState.sole.status
  end

  def test_revoked_graph_access_unpublishes_snapshots
    feed(teams_message)
    sync
    stub_request(:get, @list_url).to_return(status: 403, body: 'private-provider-body')
    assert_equal 1, sync(now: @now + 5.minutes)[:failed]
    assert_nil @unit.unit_announcements.sole.published_at
  end

  def test_deleted_source_channel_and_revoked_client_credentials_hide_snapshots
    feed(teams_message)
    sync
    stub_request(:get, @list_url).to_return(status: 404)
    assert_equal 1, sync(now: @now + 5.minutes)[:failed]
    assert_nil @unit.unit_announcements.sole.published_at
    feed(teams_message)
    sync(now: @now + 10.minutes)
    stub_request(:post, "https://login.microsoftonline.com/#{TENANT}/oauth2/v2.0/token")
      .to_return(status: 400, body: { error: 'invalid_client', error_description: 'private-provider-body' }.to_json)
    assert_equal 1, sync(now: @now + 15.minutes)[:failed]
    assert_nil @unit.unit_announcements.sole.published_at
  end

  def test_historical_scan_is_bounded_and_rotates_oldest_rows
    feed(teams_message)
    sync
    template = @unit.unit_announcements.sole
    26.times do |index|
      record = template.dup
      record.external_message_id = (5000 + index).to_s
      record.external_source_key = Digest::SHA256.hexdigest(JSON.generate([TENANT, TEAM, CHANNEL, record.external_message_id]))
      record.save!
    end
    feed
    lookup = stub_request(:get, %r{https://graph.microsoft.com#{Regexp.escape(URI::DEFAULT_PARSER.unescape(@path))}/[0-9]+$}).to_return do |request|
      { body: teams_message(request.uri.path.split('/').last).to_json }
    end
    sync(now: @now + 5.minutes)
    assert_requested lookup, times: 25
    assert_equal 2, @unit.unit_announcements.where(source_checked_at: @now).count
    sync(now: @now + 10.minutes)
    assert_equal 0, @unit.unit_announcements.where(source_checked_at: @now).count
  end

  def test_manual_row_with_colliding_external_key_is_never_overwritten
    key = Digest::SHA256.hexdigest(JSON.generate([TENANT, TEAM, CHANNEL, '12345']))
    manual = @unit.unit_announcements.create!(title: 'Manual content', body: 'Keep this', external_source_key: key)
    feed(teams_message)
    sync
    assert_equal 'Manual content', manual.reload.title
    assert_equal 'manual', manual.source_provider
    assert_equal 1, @unit.unit_announcements.count
  end

  def test_throttle_cooldown_is_persisted_and_prevents_early_retry
    request = stub_request(:get, @list_url).to_return(status: 429, headers: { 'Retry-After' => '1800' })
    assert_equal 'throttled', sync[:status]
    assert_equal @now + 30.minutes, TeamsAnnouncementSyncState.sole.next_attempt_at
    sync(now: @now + 5.minutes)
    assert_requested request, times: 1
  end

  def test_disabling_connection_removing_publishers_or_changing_tenant_hides_copies_immediately
    feed(teams_message)
    sync
    with_env { assert_equal 1, UnitAnnouncement.visible_at(@now).where(unit: @unit).count }
    [@env.merge('DF_TEAMS_ANNOUNCEMENTS_ENABLED' => 'false'),
     @env.merge('DF_TEAMS_TENANT_ID' => CLIENT),
     @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash.merge(publisher_ids: [CLIENT])].to_json)].each do |values|
      with_env(values) { assert_empty UnitAnnouncement.visible_at(@now).where(unit: @unit) }
    end
  end

  def test_still_approved_old_posts_are_revalidated_after_publisher_configuration_changes
    feed(teams_message)
    sync
    old_key = @unit.unit_announcements.sole.source_mapping_key
    feed
    stub_request(:get, "https://graph.microsoft.com#{@path}/12345").to_return(body: teams_message.to_json)
    changed = @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash.merge(publisher_ids: [PUBLISHER, CLIENT])].to_json)
    sync(now: @now + 5.minutes, env: changed)
    assert_not_equal old_key, @unit.unit_announcements.sole.source_mapping_key
    with_env(changed) { assert_equal 1, UnitAnnouncement.visible_at(@now + 5.minutes).where(unit: @unit).count }
  end

  def test_transient_failure_keeps_only_a_time_limited_snapshot
    feed(teams_message)
    sync
    stub_request(:get, @list_url).to_timeout
    sync(now: @now + 1.day)
    with_env do
      assert_equal 1, UnitAnnouncement.visible_at(@now + 1.day).where(unit: @unit).count
      assert_empty UnitAnnouncement.visible_at(@now + 8.days).where(unit: @unit)
    end
  end

  def test_source_metadata_does_not_bypass_enrolment_or_expose_integration_credentials
    feed(teams_message)
    sync
    with_env do
      add_auth_header_for(user: @student)
      get '/api/unit_hub'
      assert_equal 200, last_response.status, last_response.body
      body = JSON.parse(last_response.body)
      assert_equal 'configured', body['units'].first['teams_sync']
      row = body['announcements'].first
      assert_equal true, row['managed_externally']
      assert_equal 'Teaching team', row['author_name']
      %w[external_source_key source_mapping_key source_channel_key external_message_id].each { |key| assert_not row.key?(key) }
      assert_not_includes last_response.body, 'unit-test-secret'
      @project.update!(enrolled: false)
      get '/api/unit_hub'
      assert_empty JSON.parse(last_response.body)['announcements']
    end
  end

  def test_staff_cannot_overwrite_or_delete_imported_posts_and_disabled_sources_are_hidden_from_staff_list
    feed(teams_message)
    sync
    record = @unit.unit_announcements.sole
    add_auth_header_for(user: @unit.unit_roles.where(role: Role.convenor).first.user)
    put "/api/units/#{@unit.id}/announcements/#{record.id}", announcement: { title: 'Override' }
    assert_equal 403, last_response.status
    delete "/api/units/#{@unit.id}/announcements/#{record.id}"
    assert_equal 403, last_response.status
    with_env(@env.merge('DF_TEAMS_ANNOUNCEMENTS_ENABLED' => 'false')) do
      get "/api/units/#{@unit.id}/announcements"
      assert_empty JSON.parse(last_response.body)
    end
    assert_equal 'Weekly update', record.reload.title
  end

  def test_unit_cleanup_removes_sync_state_and_source_rows
    feed(teams_message)
    sync
    @unit.destroy!
    assert_not TeamsAnnouncementSyncState.exists?(unit_id: @unit.id)
    assert_not UnitAnnouncement.exists?(unit_id: @unit.id)
  end
end
