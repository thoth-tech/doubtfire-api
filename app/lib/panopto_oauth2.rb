require 'oauth2'
require 'rest-client'
require 'json'
require 'fileutils'

class PanoptoOAuth2
  def initialize(client_id, client_secret, server)
    @client_id = client_id
    @client_secret = client_secret
    @server = server
    @authorization_url = "https://#{server}/Panopto/oauth2/connect/authorize"
    @token_url = "https://#{server}/Panopto/oauth2/connect/token"
    @redirect_uri = 'http://localhost:9127/redirect'

    # Ensure the tmp directory exists and is writable
    FileUtils.mkdir_p(Rails.root.join('tmp')) unless File.directory?(Rails.root.join('tmp'))

    # Define the cache file path
    @cache_file = Rails.root.join('tmp', 'panopto_token_cache.json')
  end

  def get_access_token
    # Check if the cache file exists and is readable
    if File.exist?(@cache_file) && File.readable?(@cache_file)
      token_data = JSON.parse(File.read(@cache_file))
      return token_data['access_token'] if token_data['expires_at'] > Time.now.to_i
    end

    # If not valid or doesn't exist, proceed to obtain a new token
    authorize_and_get_token
  end

  private

  def authorize_and_get_token
    client = OAuth2::Client.new(@client_id, @client_secret, site: "https://#{@server}")

    scope = 'openid api offline_access'
    nonce = SecureRandom.hex(16)  # Generates a random string for nonce

    # Properly encode the scope and nonce
    encoded_scope = URI.encode_www_form_component(scope)
    encoded_nonce = URI.encode_www_form_component(nonce)

    # Construct the authorization URL
    auth_url = "https://#{@server}/Panopto/oauth2/connect/authorize?client_id=#{@client_id}&response_type=code&redirect_uri=#{@redirect_uri}&scope=#{encoded_scope}&nonce=#{encoded_nonce}"

    puts "Please visit the following URL to authorize the application: #{auth_url}"
    system("open #{auth_url}")

    # Step 2: Start the server and wait for redirect with the authorization code
    puts "Listening for authorization code at #{@redirect_uri}..."
    code = listen_for_redirect_code
    puts "Authorization code received: #{code}"

    begin
      # Use OAuth2 client to exchange the authorization code for an access token
      token = client.auth_code.get_token(code, redirect_uri: @redirect_uri)

      save_token_to_cache(token)
      token.token  # Return the access token
    rescue OAuth2::Error => e
      # Log the error response
      puts "Error during token exchange: #{e.message}"
      puts "Response status: #{e.response.status}" if e.response
      raise "Failed to get access token"
    end
  end



  def listen_for_redirect_code
    # Basic HTTP server to capture the authorization code
    server = TCPServer.new(9127)
    loop do
      client = server.accept
      request = client.gets
      if request =~ /code=(\w+)/
        client.puts "HTTP/1.1 200 OK\r\n\r\nThank you for authorizing the app. You can close this window."
        return $1
      end
    end
  end

  def save_token_to_cache(token)
    # Save the token data including expiration time
    token_data = {
      'access_token' => token.token,
      'expires_at' => Time.now.to_i + token.expires_in
    }
    File.write(@cache_file, token_data.to_json)
  end
end
