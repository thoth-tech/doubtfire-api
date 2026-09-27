# frozen_string_literal: true

class AdditionalNotificationEmailAudit < ApplicationRecord
  EVENTS = %w[
    verification_requested
    address_replaced
    verification_resent
    verification_email_delivered
    verified
    removed
    notification_copy_delivered
    notification_copy_failed
  ].freeze

  belongs_to :user

  validates :event, presence: true, inclusion: { in: EVENTS }
end
