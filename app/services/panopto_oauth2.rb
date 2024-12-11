require 'oauth2'
require 'rest-client'
require 'json'

class PanoptoOauth2
  def initialize(client_id, client_secret, server)
    @client_id = client_id
    @client_secret = client_secret
    @server = server
    @authorization_url = "https://#{server}/Panopto/oauth2/connect/authorize"
    @token_url = "https://#{server}/Panopto/oauth2/connect/token"
    @redirect_uri = 'http://localhost:9127/redirect'
  end

  def get_access_token
    # Check if the cache file exists and is readable
    token_data = JSON.parse(File.read(@cache_file)) rescue nil
    if token_data && token_data['expires_at'] > Time.now.to_i
      # Token is valid, return it
      puts "Access token from cache: #{token_data['access_token']}"
      return token_data['access_token']
    end

    # If not valid or doesn't exist, proceed to obtain a new token
    authorise_and_get_token
  end

  private

  def authorise_and_get_token
    client = OAuth2::Client.new(@client_id, @client_secret, site: "https://#{@server}")

    scope = 'openid api offline_access'
    nonce = SecureRandom.hex(16)  # Generates a random string for nonce

    # Properly encode the scope and nonce
    encoded_scope = URI.encode_www_form_component(scope)
    encoded_nonce = URI.encode_www_form_component(nonce)

    # Construct the authorisation URL
    auth_url = "https://#{@server}/Panopto/oauth2/connect/authorize?client_id=#{@client_id}&response_type=code&redirect_uri=#{@redirect_uri}&scope=#{encoded_scope}&nonce=#{encoded_nonce}"

    puts "Please visit the following URL to authorise the application: #{auth_url}"
    system("open #{auth_url}")

    # Step 2: Start the server and wait for redirect with the authorisation code
    puts "Listening for authorisation code at #{@redirect_uri}..."
    code = listen_for_redirect_code
    puts "Authorisation code received: #{code}"

    # Exchange the authorisation code for an access token
    response = RestClient.post(
      "#{@token_url}",
      {
        client_id: @client_id,
        client_secret: @client_secret,
        redirect_uri: @redirect_uri,
        code: code,
        grant_type: 'authorization_code'
      }
    )

    token_data = JSON.parse(response.body)

    # Print the access token in the terminal
    puts "Access token: #{token_data['access_token']}"

    save_token_to_cache(token_data)
    token_data['access_token']
  end


  def listen_for_redirect_code
    # Start a server to listen for the authorisation code
    server = TCPServer.new(9127)
    loop do
      client = server.accept
      request = client.gets
      if request =~ /code=(\w+)/
        client.puts "HTTP/1.1 200 OK\r\n\r\nThank you for authorising the app. You can close this window."
        return $1
      end
    end
  end

  def save_token_to_cache(token)
    token_data = {
      'access_token' => token['access_token'],
      'expires_at' => Time.now.to_i + token['expires_in']
    }
    File.write('tmp/panopto_token_cache.json', token_data.to_json)
  end
end
