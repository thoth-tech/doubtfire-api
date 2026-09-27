class ApplicationMailer < ActionMailer::Base
  # Mailer views do not pick up app helpers on their own, and the notification
  # layout needs the shared colour and glyph map for every message it renders.
  helper :notification_mail

  private

  # Build a recipient or sender address through Mail, so a display name holding a
  # quote or a comma cannot break out of the name and inject a second address,
  # and strip control characters so a name cannot fold an extra header into the
  # message. User#name comes from first_name/last_name, which are user-editable
  # and validated for presence only, so the raw %("#{name}" <#{email}>)
  # interpolation this replaces was header-injectable.
  #
  # It lives here rather than on one mailer because every mailer that addresses a
  # person needs it, and the three that did not have it were the ones still
  # interpolating by hand.
  def address_with_name(user)
    safe_name = user.name.to_s.gsub(/[[:cntrl:]]/, ' ').strip
    address = Mail::Address.new(user.email.to_s)
    address.display_name = safe_name
    address.format
  end

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
