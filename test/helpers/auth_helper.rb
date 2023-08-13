module TestHelpers
  #
  # Authentication test helper
  #
  module AuthHelper
    #
    # Gets an auth token for the provided user
    #
    def auth_token(user = User.first)
      token = user.valid_auth_tokens().first
      return token.authentication_token unless token.nil?

      return user.generate_authentication_token!().authentication_token
    end

    # 
    # Adds an authentication token and Username to the header
    # This prevents us from having to keep adding the :auth_token
    # key to any GET/POST/PUT etc. data that is needed 
    #
    def add_auth_header_for(user: User.first, username: nil, auth_token: nil)
      if username.present?
        header 'username', username
      else
        header 'username', user.username
      end

      if auth_token.present?
        header 'auth_token', auth_token
      else
        header 'auth_token', auth_token(user)
      end
    end


    module_function :auth_token
    module_function :add_auth_header_for
  end
end
