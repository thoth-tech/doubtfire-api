require 'test_helper'

# Guards the wiring in app/api/api_root.rb: every Grape API that is mounted must
# also be passed through AuthenticationHelpers.add_auth_to, unless it is on the
# short allowlist of endpoints that are deliberately public. Without this, a new
# endpoint mounted without add_auth_to ships with no authentication and nothing
# fails. The test reads the source rather than the running app so it does not
# depend on boot order or config flags.
class ApiRootTest < ActiveSupport::TestCase
  API_ROOT_PATH = Rails.root.join('app', 'api', 'api_root.rb').freeze

  # Endpoints that are public by design. Keep one comment per entry so a change
  # here is a deliberate, reviewable decision.
  PUBLIC_ALLOWLIST = [
    'ActivityTypesPublicApi',              # read-only list of activity types
    'AuthenticationApi',                   # sign in, cannot require a session
    'CampusesPublicApi',                   # read-only list of campuses
    'D2lIntegrationApi::OauthPublicApi',   # OAuth callback from D2L
    'SettingsPublicApi',                   # branding and feature flags for the login page
    'TeachingPeriodsPublicApi',            # read-only list of teaching periods
    'Tii::TurnItInHooksApi',               # inbound webhook from Turnitin, own auth
    'WebcalPublicApi'                      # calendar feed authorised by a per-user secret
  ].freeze

  # `mount SomeApi`, `mount(SomeApi)` and `mount SomeApi if <flag>` all count.
  MOUNT_LINE = /^\s*mount\b/
  MOUNT_CALL = /^\s*mount[\s(]+([A-Za-z0-9_:]+)/
  # Only an executable line counts. Anchored to the start so the class name in a
  # comment or a string cannot satisfy the guard.
  ADD_AUTH_CALL = /^\s*AuthenticationHelpers\.add_auth_to\s+([A-Za-z0-9_:]+)/

  def source
    @source ||= File.read(API_ROOT_PATH)
  end

  def mount_lines
    source.lines.select { |line| line.match?(MOUNT_LINE) }
  end

  def mounted_apis
    mount_lines.filter_map { |line| line[MOUNT_CALL, 1] }
  end

  def authenticated_apis
    source.scan(ADD_AUTH_CALL).flatten.to_set
  end

  def test_every_mounted_api_is_authenticated_or_allowlisted
    allowed = PUBLIC_ALLOWLIST.to_set
    authenticated = authenticated_apis

    unguarded = mounted_apis.reject do |api|
      authenticated.include?(api) || allowed.include?(api)
    end

    assert_empty unguarded,
      "These APIs are mounted in api_root.rb but neither pass through " \
      "AuthenticationHelpers.add_auth_to nor sit on PUBLIC_ALLOWLIST: " \
      "#{unguarded.join(', ')}. Add the endpoint to add_auth_to, or, if it is " \
      "genuinely public, add it to PUBLIC_ALLOWLIST here with a reason."
  end

  def test_allowlisted_apis_are_actually_mounted
    mounted = mounted_apis.to_set
    stale = PUBLIC_ALLOWLIST.reject { |api| mounted.include?(api) }

    assert_empty stale,
      "PUBLIC_ALLOWLIST names APIs that are no longer mounted in api_root.rb: " \
      "#{stale.join(', ')}. Remove them so the allowlist cannot mask a real gap."
  end

  # A mount written in a form this test cannot read (say a multi-line call) would
  # otherwise be dropped silently and reported as authenticated. Fail loudly so
  # the scanner is widened instead of quietly giving a false all-clear.
  def test_every_mount_line_is_parseable
    unparsed = mount_lines.reject { |line| line.match?(MOUNT_CALL) }

    assert_empty unparsed.map(&:strip),
      "These mount lines in api_root.rb could not be parsed, so the auth-coverage " \
      "guard may be skipping an endpoint. Widen MOUNT_CALL to cover them."
  end
end
