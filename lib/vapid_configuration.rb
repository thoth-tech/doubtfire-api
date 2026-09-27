# frozen_string_literal: true

require 'base64'
require 'web-push'

module VapidConfiguration
  def self.validate!(production:, environment: ENV)
    public_key = environment['DOUBTFIRE_VAPID_PUBLIC_KEY'].to_s
    private_key = environment['DOUBTFIRE_VAPID_PRIVATE_KEY'].to_s
    return if !production && public_key.empty? && private_key.empty?

    if public_key.empty? || private_key.empty?
      raise ArgumentError, 'Configure DOUBTFIRE_VAPID_PUBLIC_KEY and DOUBTFIRE_VAPID_PRIVATE_KEY before enabling production push'
    end

    begin
      decoded_public = Base64.urlsafe_decode64(public_key)
      decoded_private = Base64.urlsafe_decode64(private_key)
      raise ArgumentError unless decoded_public.bytesize == 65 && decoded_public.getbyte(0) == 4 && decoded_private.bytesize == 32

      key = WebPush::VapidKey.from_keys(public_key, private_key)
      raise ArgumentError unless key.curve.check_key
    rescue StandardError
      # Never include a key, OpenSSL diagnostic, or exception cause in boot logs.
      raise ArgumentError, 'Invalid VAPID key pair; configure a matching P-256 public/private pair', cause: nil
    end
  end
end
