#
# Records the id of an LTI token that has been used, and the user it was spent
# by, so the roles it carries are applied exactly once.
#
class ConsumedLtiToken < ApplicationRecord
  #
  # Raised when the jti of a token is already recorded. Only the insert of the
  # record raises this, so it can never be confused with an unrelated unique
  # index failure somewhere else in the enrolment.
  #
  class AlreadyUsed < StandardError; end

  belongs_to :user, inverse_of: :consumed_lti_tokens

  validates :jti, presence: true
  validates :expires_at, presence: true

  scope :expired, -> { where('expires_at < ?', Time.zone.now) }

  #
  # Record the use of a decoded LTI token. The unique index on jti means a
  # replay, including a concurrent one, fails on the insert rather than on a
  # read.
  #
  def self.consume!(token, user:)
    create!(jti: token['jti'], user: user, expires_at: Time.zone.at(token['exp'].to_i))
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyUsed
  end

  #
  # Was this token spent by this user? A launch session presents the one token
  # on every mount of the LTI dashboard, so the same person presenting it again
  # is not a replay. Anybody else is.
  #
  def spent_by?(user)
    !user.nil? && user_id == user.id
  end

  #
  # A token that has passed its expiry can no longer be replayed, so the row
  # recording it can go. Called from the maintenance:cleanup rake task.
  #
  def self.destroy_expired_tokens
    expired.destroy_all
  end
end
