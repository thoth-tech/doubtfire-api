# frozen_string_literal: true

class AdditionalNotificationEmailsApi < Grape::API
  helpers AuthenticationHelpers

  before do
    authenticated?
    header 'Cache-Control', 'private, no-store'
  end

  helpers do
    def own_user!
      error!({ error: 'You can only manage your own additional notification email.' }, 403) unless params[:user_id] == current_user.id

      current_user
    end

    def present_additional_email(record)
      if record.nil?
        { status: 'none', email: nil, verification_expires_at: nil }
      else
        {
          status: record.verified? ? 'verified' : 'pending',
          email: record.email,
          verification_expires_at: record.verification_expires_at
        }
      end
    end
  end

  desc 'Get the current user additional notification email state'
  params do
    requires :user_id, type: Integer
  end
  get '/users/:user_id/additional_notification_email' do
    user = own_user!
    present present_additional_email(user.additional_notification_email)
  end

  desc 'Request or replace an additional notification email'
  params do
    requires :user_id, type: Integer
    requires :email, type: String
  end
  put '/users/:user_id/additional_notification_email' do
    user = own_user!
    record = AdditionalNotificationEmailService.request(user: user, email: params[:email])
    present present_additional_email(record)
  rescue AdditionalNotificationEmailService::RateLimited
    error!({ error: 'Too many verification requests. Try again in one hour.' }, 429)
  end

  desc 'Resend additional notification email verification'
  params do
    requires :user_id, type: Integer
  end
  post '/users/:user_id/additional_notification_email/resend' do
    user = own_user!
    record = AdditionalNotificationEmailService.resend(user: user)
    present present_additional_email(record)
  rescue AdditionalNotificationEmailService::AlreadyVerified
    error!({ error: 'This additional notification email is already verified.' }, 409)
  rescue AdditionalNotificationEmailService::RateLimited
    error!({ error: 'Too many verification requests. Try again in one hour.' }, 429)
  end

  desc 'Remove the current user additional notification email'
  params do
    requires :user_id, type: Integer
  end
  delete '/users/:user_id/additional_notification_email' do
    user = own_user!
    AdditionalNotificationEmailService.remove(user: user)
    status 204
    body false
  end
end
