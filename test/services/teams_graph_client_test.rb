# frozen_string_literal: true

require 'test_helper'

class TeamsGraphClientTest < ActiveSupport::TestCase
  TENANT = '11111111-1111-4111-8111-111111111111'
  CLIENT = '22222222-2222-4222-8222-222222222222'
  TEAM = '33333333-3333-4333-8333-333333333333'
  PUBLISHER = '44444444-4444-4444-8444-444444444444'
  CHANNEL = '19:approved-channel@thread.tacv2'
  TOKEN_URL = "https://login.microsoftonline.com/#{TENANT}/oauth2/v2.0/token"
  PATH = "/v1.0/teams/#{TEAM}/channels/#{ERB::Util.url_encode(CHANNEL)}/messages"
  LIST_URL = "https://graph.microsoft.com#{PATH}?$top=50"

  setup do
    @mapping_hash = { unit_id: 123, team_id: TEAM, channel_id: CHANNEL, publisher_ids: [PUBLISHER], student_visible: true }
    @env = { 'DF_TEAMS_ANNOUNCEMENTS_ENABLED' => 'true', 'DF_TEAMS_TENANT_ID' => TENANT,
             'DF_TEAMS_CLIENT_ID' => CLIENT, 'DF_TEAMS_CLIENT_SECRET' => 'unit-test-secret',
             'DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash].to_json }
    @config = UnitHub::Teams::Configuration.new(@env)
    @mapping = @config.mappings.first
    @client = UnitHub::Teams::GraphClient.new(@config.credentials)
    @token_stub = stub_request(:post, TOKEN_URL).with(body: {
      client_id: CLIENT, client_secret: 'unit-test-secret', grant_type: 'client_credentials', scope: 'https://graph.microsoft.com/.default'
    }).to_return(status: 200, body: { access_token: 'test-access-token', token_type: 'Bearer' }.to_json)
  end

  def test_default_off_needs_no_credentials_or_network
    config = UnitHub::Teams::Configuration.new({})
    assert_empty config.mappings
    assert_empty config.visible_mapping_keys
    assert_equal 'disabled', UnitHub::Teams::AnnouncementSync.new(configuration: config).call[:status]
    assert_not_requested @token_stub
  end

  def test_visibility_configuration_does_not_require_client_secret
    @env.delete('DF_TEAMS_CLIENT_ID')
    @env.delete('DF_TEAMS_CLIENT_SECRET')
    config = UnitHub::Teams::Configuration.new(@env)
    assert config.configured_for?(123)
    assert_raises(UnitHub::Teams::Configuration::Error) { config.credentials }
  end

  def test_missing_student_scope_and_unapproved_publishers_are_rejected
    [@mapping_hash.except(:student_visible), @mapping_hash.merge(student_visible: false),
     @mapping_hash.merge(publisher_ids: []), @mapping_hash.merge(publisher_ids: ['not-a-guid'])].each do |mapping|
      config = UnitHub::Teams::Configuration.new(@env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [mapping].to_json))
      assert_empty config.visible_mapping_keys
      assert_raises(UnitHub::Teams::Configuration::Error) { config.mappings }
    end
    assert_not_requested @token_stub
  end

  def test_configuration_rejects_untrusted_paths_tenants_duplicates_and_excess_mappings
    [@env.merge('DF_TEAMS_TENANT_ID' => '../common'),
     @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash.merge(channel_id: '../../users')].to_json),
     @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash, @mapping_hash].to_json),
     @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => ([@mapping_hash] * 21).to_json)].each do |values|
      assert_empty UnitHub::Teams::Configuration.new(values).visible_mapping_keys
    end
  end

  def test_tenant_publisher_and_unit_changes_revoke_old_visibility_fingerprint
    original = @mapping.key
    changed_tenant = @env.merge('DF_TEAMS_TENANT_ID' => CLIENT)
    changed_publishers = @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash.merge(publisher_ids: [CLIENT])].to_json)
    changed_unit = @env.merge('DF_TEAMS_CHANNEL_MAPPINGS' => [@mapping_hash.merge(unit_id: 124)].to_json)
    [changed_tenant, changed_publishers, changed_unit].each do |values|
      assert_not_equal original, UnitHub::Teams::Configuration.new(values).mappings.first.key
    end
  end

  def test_client_credentials_and_two_bounded_pages
    next_url = "https://graph.microsoft.com#{PATH}?$skiptoken=next"
    first = stub_request(:get, LIST_URL).with(headers: { 'Authorization' => 'Bearer test-access-token' })
                                      .to_return(body: { value: [{ id: '1' }], '@odata.nextLink' => next_url }.to_json)
    second = stub_request(:get, next_url).to_return(body: { value: [{ id: '2' }], '@odata.nextLink' => "https://graph.microsoft.com#{PATH}?$skiptoken=third" }.to_json)
    assert_equal %w[1 2], @client.messages(@mapping).pluck('id')
    assert_requested @token_stub, times: 1
    assert_requested first, times: 1
    assert_requested second, times: 1
  end

  def test_next_links_cannot_escape_the_configured_channel_or_leak_the_token
    ["https://evil.example#{PATH}", 'https://graph.microsoft.com/v1.0/users',
     "https://graph.microsoft.com:444#{PATH}", "https://user@graph.microsoft.com#{PATH}",
     "https://graph.microsoft.com#{PATH}#fragment", "http://graph.microsoft.com#{PATH}"].each do |url|
      stub_request(:get, LIST_URL).to_return(body: { value: [], '@odata.nextLink' => url }.to_json)
      assert_raises(UnitHub::Teams::GraphClient::Error) { @client.messages(@mapping) }
    end
  end

  def test_redirects_and_provider_errors_do_not_expose_body_or_credentials
    stub_request(:get, LIST_URL).to_return(status: 302, headers: { 'Location' => 'https://evil.example' }, body: 'private-provider-body')
    error = assert_raises(UnitHub::Teams::GraphClient::Error) { @client.messages(@mapping) }
    assert_not_includes error.message, 'private-provider-body'
    assert_not_includes error.message, 'test-access-token'
    assert_requested @token_stub, times: 1
  end

  def test_invalid_json_oversized_body_and_malformed_http_are_sanitized
    stub_request(:get, LIST_URL).to_return(body: 'private-provider-body')
    assert_raises(UnitHub::Teams::GraphClient::Error) { @client.messages(@mapping) }
    stub_request(:get, LIST_URL).to_return(body: 'x' * (2.megabytes + 1))
    assert_raises(UnitHub::Teams::GraphClient::Error) { @client.messages(@mapping) }
    stub_request(:get, LIST_URL).to_raise(Net::HTTPBadResponse.new('private-provider-body'))
    error = assert_raises(UnitHub::Teams::GraphClient::Error) { @client.messages(@mapping) }
    assert_not_includes error.message, 'private-provider-body'
  end

  def test_throttling_preserves_bounded_retry_after
    stub_request(:get, LIST_URL).to_return(status: 429, headers: { 'Retry-After' => '1800' })
    error = assert_raises(UnitHub::Teams::GraphClient::Throttled) { @client.messages(@mapping) }
    assert_equal 1800, error.retry_after
  end

  def test_overall_deadline_prevents_network_access
    client = UnitHub::Teams::GraphClient.new(@config.credentials, deadline: 0)
    assert_raises(UnitHub::Teams::GraphClient::Error) { client.messages(@mapping) }
    assert_not_requested @token_stub
  end
end
