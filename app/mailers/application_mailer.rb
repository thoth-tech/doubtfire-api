class ApplicationMailer < ActionMailer::Base
  private

  # Azure Communication Services only accepts a verified sender in From.
  # Keep the existing per-user From address outside production so local mail
  # previews and development SMTP retain their current behaviour. In
  # production, callers may preserve the human sender as Reply-To.
  def outbound_sender_headers(development_from:, reply_to: nil)
    return { from: development_from } unless Rails.env.production?

    configured_sender = Doubtfire::Application.config.institution[:email_sender].presence
    raise ArgumentError, 'institution email_sender must be configured in production' if configured_sender.blank?

    headers = { from: configured_sender }
    headers[:reply_to] = reply_to if reply_to.present?
    headers
  end
end
