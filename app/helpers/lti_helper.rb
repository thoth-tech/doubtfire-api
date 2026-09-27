module LtiHelper
  def decode_lti_token(token)
    begin
      secret_key = Doubtfire::Application.config.lti_api_secret
      response = JWT.decode(token, secret_key, true, algorithm: 'HS256').first

      jti = response['jti']
      exp = response['exp']

      # An empty jti is no more usable than a missing one, it cannot be
      # recorded and so it cannot be spent.
      raise "Missing jti" if jti.blank?
      raise "Missing exp" if exp.nil?
    rescue JWT::DecodeError => e
      logger.debug "Failed to validate Lti Token: #{e}"
      return error!({ error: 'Invalid LTI token.' }, 403)
    rescue StandardError => e
      logger.debug "Missing token properties: #{e}"
      return error!({ error: 'Invalid LTI token.' }, 403)
    end
    response
  end

  def valid_lti_member?(member)
    required_fields = %w[user_id email roles given_name family_name name]
    missing = required_fields.select { |f| member[f].nil? || member[f].to_s.strip.empty? }
    [missing.empty?, missing]
  end

  #
  # The identity fields an LTI member maps onto a Doubtfire user. This is the
  # mapping the LTI sign in already uses.
  #
  def lti_member_user_id_data(member)
    {
      login_id: member['ext_user_username'] || member['user_id'],
      email: member['email'],
      username: member['email']&.split('@')&.first
    }
  end

  #
  # Is this signed in user the person the LTI member describes?
  #
  # Only the login_id and the email are asserted by the platform. The username
  # is derived from the local part of the email, which is not unique across
  # domains, so it is never enough on its own to say a token belongs to
  # somebody.
  #
  def lti_member_is?(member, user)
    return false if user.nil?

    id_data = lti_member_user_id_data(member)

    # The login_id is the strongest thing the platform asserts about the person,
    # so when both sides carry one it settles the question by itself. Falling
    # through to the email after a mismatch would let a token issued for somebody
    # else bind to this user on a shared or reused address.
    if id_data[:login_id].present? && user.login_id.present?
      return user.login_id == id_data[:login_id]
    end

    # No login_id on one side or the other, so the email is all that is left.
    id_data[:email].present? && user.email.present? && user.email.casecmp?(id_data[:email])
  end
end
