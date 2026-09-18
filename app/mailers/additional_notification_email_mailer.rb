# frozen_string_literal: true

class AdditionalNotificationEmailMailer < ApplicationMailer
  def verification(record)
    @user = record.user
    @product_name = Doubtfire::Application.config.institution[:product_name]
    host = Doubtfire::Application.config.institution[:host].to_s.delete_suffix('/')
    token_query = URI.encode_www_form(token: record.verification_token)
    @verification_url = "#{host}/verify_additional_email##{token_query}"

    sender = Doubtfire::Application.config.institution[:email_sender].presence ||
             'noreply@doubtfire.local'

    mail(
      to: record.email,
      subject: "Verify your additional #{@product_name} notification email",
      **outbound_sender_headers(development_from: sender)
    )
  end
end
