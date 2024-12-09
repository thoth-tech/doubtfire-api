class VideosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:upload_video]

  def upload_video
    # Log all parameters received
    puts "All parameters: #{params.inspect}"

    # Extract parameters
    client_id = params[:client_id]
    client_secret = params[:client_secret]
    server = params[:server]
    folder_id = params[:folder_id]
    file_path = params[:video][:file_path]  # Correctly access file_path

    # Log the specific parameters
    puts "Parameters received: client_id=#{client_id}, client_secret=#{client_secret}, server=#{server}, folder_id=#{folder_id}, file_path=#{file_path}"

    begin
      panopto_oauth = PanoptoOauth2.new(client_id, client_secret, server)
      panopto_uploader = PanoptoUploader.new(server, panopto_oauth)

      # Create session
      puts "Creating session for folder_id: #{folder_id}"
      session_response = panopto_uploader.create_session(folder_id)
      puts "Session response: #{session_response.inspect}"

      # Upload video
      puts "Uploading video from path: #{file_path}"
      panopto_uploader.upload_video(file_path)

      render json: { message: 'Video uploaded successfully' }, status: 200
    rescue StandardError => e
      puts "Error during video upload: #{e.message}"
      render json: { error: "Failed to upload video: #{e.message}" }, status: 500
    end
  end
end
