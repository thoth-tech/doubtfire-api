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
      username: 'metoo',
      password: 'password',
      password_confirmation: 'password'
    }
    User.create!(profile)
    assert User.last, profile
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
end
