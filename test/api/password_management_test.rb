require 'test_helper'

class PasswordManagementTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @user = User.create!(
      username: 'testuser',
      email: 'test@example.com',
      first_name: 'Test',
      last_name: 'User',
      password: 'password123',
      password_confirmation: 'password123',
      role_id: Role.student.id,
      login_id: 'testuser'
    )
  end

  test "should register new user with valid data" do
    post '/api/register', params: {
      username: 'newuser',
      email: 'newuser@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'New',
      last_name: 'User'
    }

    assert_response :success
    assert_equal 'newuser', JSON.parse(response.body)['user']['username']
    assert_not_nil JSON.parse(response.body)['auth_token']
  end

  test "should not register user with existing username" do
    post '/api/register', params: {
      username: 'testuser',
      email: 'different@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Different',
      last_name: 'User'
    }

    assert_response :conflict
    assert_includes JSON.parse(response.body)['error'], 'Username already exists'
  end

  test "should not register user with existing email" do
    post '/api/register', params: {
      username: 'differentuser',
      email: 'test@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Different',
      last_name: 'User'
    }

    assert_response :conflict
    assert_includes JSON.parse(response.body)['error'], 'Email already exists'
  end

  test "should not register user with short password" do
    post '/api/register', params: {
      username: 'newuser',
      email: 'newuser@example.com',
      password: 'short',
      password_confirmation: 'short',
      first_name: 'New',
      last_name: 'User'
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)['details'], 'Password is too short'
  end

  test "should not register user with mismatched passwords" do
    post '/api/register', params: {
      username: 'newuser',
      email: 'newuser@example.com',
      password: 'password123',
      password_confirmation: 'different123',
      first_name: 'New',
      last_name: 'User'
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)['details'], "doesn't match password"
  end

  test "should request password reset for existing user" do
    assert_emails 1 do
      post '/api/password/reset', params: { email: 'test@example.com' }
    end

    assert_response :success
    assert_includes JSON.parse(response.body)['message'], 'password reset link has been sent'
    
    @user.reload
    assert_not_nil @user.reset_password_token
    assert_not_nil @user.reset_password_sent_at
    
    # Check that the email was sent
    email = ActionMailer::Base.deliveries.last
    assert_equal 'test@example.com', email.to[0]
    assert_includes email.subject, 'Password Reset Request'
  end

  test "should not reveal if email exists for password reset" do
    post '/api/password/reset', params: { email: 'nonexistent@example.com' }

    assert_response :success
    assert_includes JSON.parse(response.body)['message'], 'password reset link has been sent'
  end

  test "should reset password with valid token" do
    @user.generate_password_reset_token!
    token = @user.reset_password_token

    assert_emails 1 do
      post '/api/password/reset/confirm', params: {
        token: token,
        password: 'newpassword123',
        password_confirmation: 'newpassword123'
      }
    end

    assert_response :success
    assert_includes JSON.parse(response.body)['message'], 'Password has been reset'

    @user.reload
    assert_nil @user.reset_password_token
    assert_nil @user.reset_password_sent_at
    assert @user.valid_password?('newpassword123')
    
    # Check that the password changed notification email was sent
    email = ActionMailer::Base.deliveries.last
    assert_equal 'test@example.com', email.to[0]
    assert_includes email.subject, 'Password Changed Successfully'
  end

  test "should not reset password with invalid token" do
    post '/api/password/reset/confirm', params: {
      token: 'invalid_token',
      password: 'newpassword123',
      password_confirmation: 'newpassword123'
    }

    assert_response :bad_request
    assert_includes JSON.parse(response.body)['error'], 'Invalid or expired reset token'
  end

  test "should change password with correct current password" do
    auth_token = @user.generate_authentication_token!(false).authentication_token

    assert_emails 1 do
      post '/api/password/change', params: {
        current_password: 'password123',
        password: 'newpassword123',
        password_confirmation: 'newpassword123'
      }, headers: {
        'Auth-Token' => auth_token,
        'Username' => @user.username
      }
    end

    assert_response :success
    assert_includes JSON.parse(response.body)['message'], 'Password has been changed'

    @user.reload
    assert @user.valid_password?('newpassword123')
    
    # Check that the password changed notification email was sent
    email = ActionMailer::Base.deliveries.last
    assert_equal 'test@example.com', email.to[0]
    assert_includes email.subject, 'Password Changed Successfully'
  end

  test "should not change password with incorrect current password" do
    auth_token = @user.generate_authentication_token!(false).authentication_token

    post '/api/password/change', params: {
      current_password: 'wrongpassword',
      password: 'newpassword123',
      password_confirmation: 'newpassword123'
    }, headers: {
      'Auth-Token' => auth_token,
      'Username' => @user.username
    }

    assert_response :bad_request
    assert_includes JSON.parse(response.body)['error'], 'Current password is incorrect'
  end

  test "should require authentication for password change" do
    post '/api/password/change', params: {
      current_password: 'password123',
      password: 'newpassword123',
      password_confirmation: 'newpassword123'
    }

    assert_response :unauthorized
  end
end
