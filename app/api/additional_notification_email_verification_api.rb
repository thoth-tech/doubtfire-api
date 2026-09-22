# frozen_string_literal: true

class AdditionalNotificationEmailVerificationApi < Grape::API
  desc 'Verify ownership of an additional notification email'
  params do
    requires :token, type: String
  end
  post '/additional_notification_emails/verify' do
    header 'Cache-Control', 'private, no-store'
    AdditionalNotificationEmailService.verify(token: params[:token])
    { status: 'verified' }
  rescue AdditionalNotificationEmailService::AlreadyVerified
    error!({ error: 'This verification link has already been used.' }, 409)
  rescue AdditionalNotificationEmailService::InvalidToken
    error!({ error: 'This verification link is invalid or has expired.' }, 422)
  end
end
