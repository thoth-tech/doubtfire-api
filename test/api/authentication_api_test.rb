require 'test_helper'
require 'securerandom'

#
# Tests that a federated sign in resolves to the person the assertion is
# actually about. The LTI callback is the federated path that is mounted in the
# test environment, so it stands in for the SAML and AAF callbacks and for the
# LTI membership import job, which share the same lookup helper.
#
class AuthenticationApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def lti_token_for(member)
    JWT.encode({
                 member: member,
                 exp: Time.now.to_i + 30,
                 jti: SecureRandom.uuid
               }, Doubtfire::Application.config.lti_api_secret, 'HS256')
  end

  def lti_member(login_id:, email:)
    {
      user_id: SecureRandom.uuid,
      name: 'Nickname',
      given_name: 'First name',
      family_name: 'Last name',
      email: email,
      ext_user_username: login_id,
      roles: ['Learner']
    }
  end

  # An assertion whose login_id matches an existing account resolves to it.
  def test_assertion_resolves_on_matching_login_id
    user = FactoryBot.create(:user, username: 'sec07-known', email: 'sec07-known@example.com')
    user.update(login_id: 'sec07-known-login')

    user_count = User.count

    post '/api/auth/lti', { ltik: lti_token_for(lti_member(login_id: 'sec07-known-login', email: 'sec07-known@example.com')) }

    assert_equal 201, last_response.status, last_response_body
    assert_equal user.username, last_response_body['username']
    assert_equal user_count, User.count, 'Matching on login_id must not create a user'
  end

  # Once an account and an assertion both carry a login id, that identifier has
  # to decide the match on its own. Falling through to a shared or reused email
  # address after a mismatch would issue a login token for the wrong account.
  def test_assertion_does_not_fall_back_to_email_after_a_login_id_mismatch
    account = FactoryBot.create(:user, username: 'sec07-email-owner', email: 'sec07-shared@example.com')
    account.update(login_id: 'sec07-email-owner-login')

    user_count = User.count

    post '/api/auth/lti', {
      ltik: lti_token_for(lti_member(login_id: 'sec07-other-login', email: 'sec07-shared@example.com'))
    }

    assert_equal 500, last_response.status, 'A mismatched asserted login id must not be rescued by the email'
    assert_nil last_response_body['auth_token'], 'No token may be issued for the email owner'
    assert_equal user_count, User.count, 'A refused assertion must not create an account'

    account.reload
    assert_equal 'sec07-email-owner-login', account.login_id
    assert_nil account.auth_tokens.first, 'No token may be issued for the unrelated account'
  end

  # An assertion whose derived username collides with an unrelated account must
  # not resolve to that account. The derived username is the local part of the
  # asserted email, so two people at different domains derive the same one.
  # Nothing the provider asserted matches, so the callback tries to create an
  # account and the username the assertion derives is already taken.
  def test_assertion_does_not_resolve_on_a_colliding_derived_username
    unrelated = FactoryBot.create(:user, username: 'sec07-shared', email: 'sec07-shared@one.example.com')
    unrelated.update(login_id: 'sec07-unrelated-login')

    user_count = User.count

    post '/api/auth/lti', { ltik: lti_token_for(lti_member(login_id: 'sec07-other-login', email: 'sec07-shared@two.example.com')) }

    assert_equal 500, last_response.status, 'A colliding assertion must be refused, not resolved'
    assert_nil last_response_body['auth_token'], 'No token may be issued on a refused assertion'
    assert_equal user_count, User.count, 'A refused assertion must not create an account'

    unrelated.reload
    assert_equal 'sec07-unrelated-login', unrelated.login_id, 'The unrelated account must not be taken over'
    assert_equal 'sec07-shared@one.example.com', unrelated.email, 'The unrelated account must not be rewritten'
    assert_nil unrelated.auth_tokens.first, 'No token may be issued for the unrelated account'
  end

  # An account created before the institution had an identity provider is
  # adopted at its first federated sign in on the asserted email, so removing
  # the username lookup does not orphan it.
  def test_pre_federation_account_is_adopted_on_the_asserted_email
    legacy = FactoryBot.create(:user, username: 'sec07-legacy', email: 'sec07-legacy@example.com')
    legacy.update(login_id: nil)

    user_count = User.count

    post '/api/auth/lti', { ltik: lti_token_for(lti_member(login_id: 'sec07-legacy-login', email: 'sec07-legacy@example.com')) }

    assert_equal 201, last_response.status, last_response_body
    assert_equal legacy.username, last_response_body['username']
    assert_equal user_count, User.count, 'A pre federation account must be adopted, not duplicated'

    legacy.reload
    assert_equal 'sec07-legacy-login', legacy.login_id
  end

  # A pre federation account whose stored email is not the asserted one is no
  # longer adopted on its username, because the username is not asserted. The
  # sign in is refused and an administrator has to correct the stored email or
  # login_id before that person can sign in.
  def test_pre_federation_account_with_a_different_stored_email_is_not_adopted
    legacy = FactoryBot.create(:user, username: 'sec07-moved', email: 'sec07-moved@old.example.com')
    legacy.update(login_id: nil)

    user_count = User.count

    post '/api/auth/lti', { ltik: lti_token_for(lti_member(login_id: 'sec07-moved-login', email: 'sec07-moved@new.example.com')) }

    assert_equal 500, last_response.status, 'An unasserted username must not resolve the account'
    assert_equal user_count, User.count

    legacy.reload
    assert_nil legacy.login_id, 'The account must not have a login_id installed on it'
    assert_equal 'sec07-moved@old.example.com', legacy.email
  end

  # A legacy account with no email recorded holds a username but nothing the
  # provider can assert, so an assertion that derives that username must not
  # pick it up either. Matching it would hand the account to whoever registers
  # the same local part at any domain.
  def test_legacy_account_with_a_blank_email_is_not_taken_over
    legacy = FactoryBot.create(:user, username: 'sec07-blank', email: 'sec07-blank@example.com')
    legacy.update(login_id: nil)
    legacy.update_column(:email, '')

    user_count = User.count

    post '/api/auth/lti', { ltik: lti_token_for(lti_member(login_id: 'sec07-attacker-login', email: 'sec07-blank@attacker.example.com')) }

    assert_equal 500, last_response.status, 'A blank email account must not be matched on its username'
    assert_nil last_response_body['auth_token'], 'No token may be issued on a refused assertion'
    assert_equal user_count, User.count

    legacy.reload
    assert_nil legacy.login_id, 'The blank email account must not be taken over'
    assert_nil legacy.auth_tokens.first, 'No token may be issued for the blank email account'
  end

  # The normal path. A first time user is still created.
  def test_first_time_user_is_still_created
    user_count = User.count

    post '/api/auth/lti', { ltik: lti_token_for(lti_member(login_id: 'sec07-new-login', email: 'sec07-new@example.com')) }

    assert_equal 201, last_response.status, last_response_body
    assert_equal 'sec07-new', last_response_body['username']
    assert_equal user_count + 1, User.count

    created = User.find_by(username: 'sec07-new')
    assert_not_nil created
    assert_equal 'sec07-new-login', created.login_id
    assert_equal 'sec07-new@example.com', created.email
  end
end
