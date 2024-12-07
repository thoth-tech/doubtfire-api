require 'panopto_oauth2'

class VideosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:upload_video]
  def upload_video
    # Extract client_id, client_secret, and server from parameters
    client_id = params[:client_id]
    client_secret = params[:client_secret]
    server = params[:server]

    # Initialize the OAuth2 client
    panopto_oauth = PanoptoOAuth2.new(client_id, client_secret, server)

    # Get the access token
    begin
      access_token = panopto_oauth.get_access_token
      puts "Access token: #{access_token}"
    rescue => e
      puts "Failed to get access token: #{e.message}"
      render json: { error: "Failed to authenticate with Panopto" }, status: 500
      return
    end

    # Now you can proceed with the video upload process
    # Example: upload the video using the access token

    render json: { message: "Successfully obtained access token" }
  end
end
