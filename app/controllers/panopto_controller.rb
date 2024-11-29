class PanoptoController < ApplicationController
  require 'rest-client'
  require 'json'

  # OAuth2 Callback
  def callback
    # Exchange the authorization code for an access token
    response = RestClient.post("#{ENV['PANOPTO_BASE_URL']}/Panopto/oauth2/connect/token", {
      client_id: ENV['PANOPTO_CLIENT_ID'],
      client_secret: ENV['PANOPTO_CLIENT_SECRET'],
      redirect_uri: ENV['PANOPTO_REDIRECT_URI'],
      code: params[:code],
      grant_type: 'authorization_code'
    })

    # Store the access token in the session for future requests
    session[:panopto_access_token] = JSON.parse(response.body)['access_token']
    flash[:notice] = 'Authentication successful!'

    redirect_to root_path # Redirect to a meaningful page after authentication
  rescue RestClient::ExceptionWithResponse => e
    flash[:alert] = 'Authentication failed!'
    redirect_to root_path
  end

  # Video Upload
  def upload
    # Ensure we have an access token
    unless session[:panopto_access_token]
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    # Prepare the file and make the API request
    file = params[:file]
    response = RestClient.post("#{ENV['PANOPTO_BASE_URL']}/Panopto/api/v1/videos",
      { file: file },
      { Authorization: "Bearer #{session[:panopto_access_token]}" }
    )

    # Render the API response back to the client
    render json: { status: 'success', data: JSON.parse(response.body) }
  rescue RestClient::ExceptionWithResponse => e
    render json: { error: JSON.parse(e.response.body) }, status: :unprocessable_entity
  end

  # Metadata Retrieval
  def metadata
    # Ensure we have an access token
    unless session[:panopto_access_token]
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    # Fetch metadata for the given video ID
    response = RestClient.get("#{ENV['PANOPTO_BASE_URL']}/Panopto/api/v1/videos/#{params[:id]}",
      { Authorization: "Bearer #{session[:panopto_access_token]}" }
    )

    # Render the API response back to the client
    render json: { status: 'success', data: JSON.parse(response.body) }
  rescue RestClient::ExceptionWithResponse => e
    render json: { error: JSON.parse(e.response.body) }, status: :unprocessable_entity
  end
end
