# frozen_string_literal: true

class AdditionalNotificationEmail < ApplicationRecord
  TOKEN_PURPOSE = 'additional-notification-email-verification'
  EMAIL_FORMAT = /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i

  belongs_to :user

  before_validation :normalise_email

  validates :email,
            presence: true,
            length: { maximum: 254 },
            format: { with: EMAIL_FORMAT }
  validates :verification_version,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :must_differ_from_primary_email

  scope :verified, -> { where.not(verified_at: nil) }

  def pending?
    verified_at.nil?
  end

  def verified?
    verified_at.present?
  end

  def verification_expired?
    verification_expires_at.blank? || verification_expires_at <= Time.current
  end

  # The token is signed rather than stored. Jobs carry only this record's id
  # and version, while a replacement or resend increments the version and
  # immediately invalidates every earlier link.
  def verification_token
    raise 'Cannot issue an expired verification token' if verification_expired?

    self.class.token_verifier.generate(
      { id: id, version: verification_version },
      expires_in: verification_expires_at - Time.current,
      purpose: TOKEN_PURPOSE
    )
  end

  def self.record_for_token(token)
    payload = token_verifier.verified(token.to_s, purpose: TOKEN_PURPOSE)
    return nil unless payload.is_a?(Hash)

    record = find_by(id: payload['id'] || payload[:id])
    return nil if record.nil? || record.verification_expired?
    return nil unless record.verification_version == (payload['version'] || payload[:version]).to_i

    record
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.token_verifier
    ActiveSupport::MessageVerifier.new(
      Rails.application.secret_key_base,
      digest: 'SHA256',
      serializer: JSON
    )
  end

  private

  def normalise_email
    self.email = email.to_s.strip.downcase
  end

  def must_differ_from_primary_email
    return if user.nil? || email.blank?
    return unless email.casecmp?(user.email.to_s.strip)

    errors.add(:email, 'must be different from the institutional email')
  end
end
