class VideosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:get_access_token]

  def get_access_token
    # Extract parameters from the request
    client_id = params[:client_id]
    client_secret = params[:client_secret]
    server = params[:server]

    begin
      # Initialise the OAuth2 service
      panopto_oauth = PanoptoOauth2.new(client_id, client_secret, server)
      # Get the access token
      access_token = panopto_oauth.get_access_token

      render json: { access_token: access_token }, status: 200
    rescue StandardError => e
      render json: { error: "Failed to get access token: #{e.message}" }, status: 500
    end
  end
end
