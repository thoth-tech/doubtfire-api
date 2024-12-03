require_dependency "#{Rails.root}/app/lib/panopto_oauth2"

class VideosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:upload_video]

  def upload_video
    # Step 1: OAuth2 authentication
    oauth2 = PanoptoOAuth2.new(params[:client_id], params[:client_secret], params[:server])
    access_token = oauth2.get_access_token

    # Step 2: Create upload session
    upload_session = create_upload_session(params[:folder_id], access_token)

    # Step 3: Upload video
    upload_video_file(upload_session[:upload_target], params[:file_path], access_token)

    # Step 4: Create and upload manifest file
    manifest_file = create_manifest(params[:file_path])
    upload_file(upload_session[:upload_target], manifest_file, access_token)

    # Step 5: Finish the upload
    complete_upload(upload_session[:upload_id], access_token)

    render json: { message: 'Upload completed successfully' }
  end

  private

  def create_upload_session(folder_id, access_token)
    # POST request to create upload session
    response = RestClient.post(
      "https://#{params[:server]}/Panopto/PublicAPI/Rest/sessionUpload",
      { folder_id: folder_id }.to_json,
      { Authorization: "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  end

  def upload_video_file(upload_target, file_path, access_token)
    # Use AWS SDK to upload video in parts (implementing multipart upload here)
    s3 = Aws::S3::Resource.new(region: 'us-east-1')
    bucket = s3.bucket(upload_target)
    obj = bucket.object(File.basename(file_path))
    obj.upload_file(file_path)
  end

  def create_manifest(file_path)
    # Generate the manifest XML based on the file
    manifest_template = File.read('app/assets/templates/upload_manifest_template.xml')
    manifest = manifest_template.gsub('{Filename}', File.basename(file_path))
    File.write('tmp/generated_manifest.xml', manifest)
    'tmp/generated_manifest.xml'
  end

  def upload_file(upload_target, file_path, access_token)
    # Upload the manifest file (similar to video file upload)
    s3 = Aws::S3::Resource.new(region: 'us-east-1')
    bucket = s3.bucket(upload_target)
    obj = bucket.object(File.basename(file_path))
    obj.upload_file(file_path)
  end

  def complete_upload(upload_id, access_token)
    # PUT request to complete the upload session
    response = RestClient.put(
      "https://#{params[:server]}/Panopto/PublicAPI/Rest/sessionUpload/#{upload_id}",
      { state: '1' }.to_json,
      { Authorization: "Bearer #{access_token}" }
    )
    JSON.parse(response.body)
  end
end
