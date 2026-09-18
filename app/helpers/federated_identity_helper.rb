#
# Resolves the user that a federated assertion is about.
#
# The identity provider asserts a login_id and an email, and those are the only
# two things a federated sign in may be matched on. The username is derived from
# the local part of the email, so two people at different domains derive the
# same one and an account found that way is not necessarily the person the
# assertion is about.
#
module FederatedIdentityHelper
  include LogHelper

  #
  # Find the existing user this assertion is about, or nil so the caller creates
  # one. Source is what a near miss gets logged against, the request ip for a
  # sign in and the job context for a background import.
  #
  def user_for_asserted_identity(login_id:, email:, derived_username:, source:)
    if login_id.present?
      user = User.find_by(login_id: login_id)
      return user unless user.nil?
    end

    if email.present?
      user = User.find_by(email: email)

      # A pre-federation account with no login id can be adopted on its asserted
      # email. Once both the assertion and the account carry a login id, though,
      # a mismatch settles the question: falling through to email would hand a
      # shared or reused address to the wrong federated identity.
      return user if user.present? && (login_id.blank? || user.login_id.blank?)

      unless user.nil?
        logger.info "Refused email fallback for #{login_id} from #{source}"
        return nil
      end
    end

    log_refused_username_match(login_id, derived_username, source)
    nil
  end

  private

  #
  # An account already holds the username this assertion derives, and nothing
  # the provider asserted matched it. Somebody investigating a duplicate account
  # or a failed sign in later needs to see the near miss. The assertion itself
  # is never logged.
  #
  def log_refused_username_match(login_id, derived_username, source)
    return if derived_username.blank?
    return unless User.exists?(username: derived_username)

    logger.info "Refused username match for #{login_id} from #{source}"
  end
end
