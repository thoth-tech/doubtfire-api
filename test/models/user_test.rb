require 'test_helper'

class UserTest < ActiveSupport::TestCase
  setup do
    @user = User.first
  end

  test 'user authentication post' do
    assert      @user.authenticate? 'password'
    assert_not  @user.authenticate? 'potato'
  end

  test 'create user' do
    profile = {
      first_name: 'Test',
      last_name: 'Test',
      nickname: 'Test',
      role_id: 1,
      email: 'test@test.org',
      username: 'metoo'
    }
    user = User.new(profile)
    user.password = 'password'
    user.save!

    assert_equal profile.stringify_keys, user.attributes.slice(*profile.stringify_keys.keys)
    assert user.authenticate?('password')
    assert User.last.display_peer_progress?
  end

  def test_user_is_valid
    user = FactoryBot.create(:user)
    assert user.valid?
  end

  def test_invalid_without_first_name
    user = FactoryBot.build(:user, first_name: nil)
    refute user.valid?
  end

  def test_invalid_without_last_name
    user = FactoryBot.build(:user, last_name: nil)
    refute user.valid?
  end

  def test_can_create_multiple_auth_tokens
    user = FactoryBot.create(:user)
    t1 = user.generate_authentication_token!
    t2 = user.generate_authentication_token!
    assert_not_equal t1, t2
  end

  def test_valid_theme_preferences
    [nil, 'light', 'dark', 'system'].each do |theme|
      user = FactoryBot.build(:user, theme_preference: theme)
      assert user.valid?, "expected #{theme.inspect} to be a valid theme_preference"
    end
  end

  def test_invalid_theme_preference
    user = FactoryBot.build(:user, theme_preference: 'sepia')
    refute user.valid?
  end

  def test_theme_preference_timestamp_tracks_actual_preference_changes
    user = FactoryBot.create(:user)

    assert_nil user.theme_preference
    assert_nil user.theme_preference_updated_at

    first_choice_at = Time.zone.parse('2026-08-30 10:00:00 UTC')
    travel_to first_choice_at do
      user.update!(theme_preference: 'dark')
    end
    assert_equal first_choice_at, user.theme_preference_updated_at

    travel_to first_choice_at + 30.minutes do
      user.update!(theme_preference: 'dark')
    end
    assert_equal first_choice_at, user.theme_preference_updated_at,
                 'model writes of the same value are not API synchronization writes'

    travel_to first_choice_at + 1.hour do
      user.update!(nickname: 'Still dark')
    end
    assert_equal first_choice_at, user.theme_preference_updated_at,
                 'unrelated updates must not make the preference look newer'

    second_choice_at = first_choice_at + 2.hours
    travel_to second_choice_at do
      user.update!(theme_preference: 'light')
    end
    assert_equal second_choice_at, user.theme_preference_updated_at
  end

  def test_clearing_theme_preference_restores_the_never_chosen_state
    user = FactoryBot.create(:user, theme_preference: 'dark')
    assert_not_nil user.theme_preference_updated_at

    user.update!(theme_preference: nil)

    assert_nil user.theme_preference
    assert_nil user.theme_preference_updated_at
  end
end
