class PanoptoUploader
  def initialize(server, oauth2)
    @server = server
    @oauth2 = oauth2
    @upload_target = nil
    @session_id = nil
    @access_token = oauth2.get_access_token
  end

  # Create a session for the video upload
  def create_session(folder_id)
    url = "https://#{@server}/Panopto/PublicAPI/REST/sessionUpload"

    payload = {
      "FolderId" => folder_id
    }

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{@access_token}"
    }

    begin
      puts "Calling POST PublicAPI/REST/sessionUpload endpoint"
      response = RestClient.post(url, payload.to_json, headers)

      # Log the response
      puts "Response Status: #{response.code}"
      puts "Response Body: #{response.body}"

      session = JSON.parse(response.body)
      @upload_target = session['UploadTarget']
      @session_id = session['ID']

      # Ensure that UploadTarget and Session ID are not nil
      raise "UploadTarget or Session ID is nil" if @upload_target.nil? || @session_id.nil?

      puts "Session created with ID: #{@session_id}, Upload Target: #{@upload_target}"

      return session
    rescue RestClient::ExceptionWithResponse => e
      puts "Error during session creation: #{e.response}"
      return nil
    end
  end

  # Upload the video and monitor the upload status
  def upload_video(file_path)
    # Step 1: Create the session
    session = create_session('d09c50e9-c4a6-44dc-a6d8-b2370099a751')
    return unless session

    upload_target = session['UploadTarget']
    session_id = session['ID']

    # Step 2: Upload the video file
    upload_file(upload_target, file_path)

    # Step 3: Create the manifest file and upload it
    create_manifest(file_path)
    upload_file(upload_target, 'upload_manifest_generated.xml')

    # Step 4: Finish the upload session
    finish_upload(session_id)

    # Step 5: Monitor the progress of the upload
    monitor_upload_progress(session_id)
  end

  # Upload a file using multipart upload
  def upload_file(upload_target, file_path)
    s3_client = Aws::S3::Client.new(endpoint: "https://#{upload_target}/")
    bucket, prefix = upload_target.split('/').last(2)

    object_key = "#{prefix}/#{File.basename(file_path)}"
    File.open(file_path, 'rb') do |file|
      s3_client.put_object(bucket: bucket, key: object_key, body: file)
    end

    puts "Uploaded file: #{file_path} to #{@upload_target}"
  end

  # Create a manifest file
  def create_manifest(file_path)
    manifest_content = <<-XML
    <?xml version="1.0" encoding="utf-8"?>
    <Session xmlns="http://tempuri.org/UniversalCaptureSpecification/v1">
      <Title>#{File.basename(file_path)}</Title>
      <Description>Uploaded video</Description>
      <Date>#{Time.now.utc}</Date>
      <Videos>
        <Video>
          <Start>PT0S</Start>
          <File>#{File.basename(file_path)}</File>
          <Type>Primary</Type>
        </Video>
      </Videos>
    </Session>
    XML

    File.write('upload_manifest_generated.xml', manifest_content)
    puts "Manifest file created."
  end

  # Finalize the upload session
  def finish_upload(session_id)
    url = "https://#{@server}/Panopto/PublicAPI/REST/sessionUpload/#{session_id}"
    payload = { "State" => 1, "FolderId" => 'd09c50e9-c4a6-44dc-a6d8-b2370099a751' }
    headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{@access_token}" }

    response = RestClient.put(url, payload.to_json, headers)
    puts "Upload session completed."
  rescue RestClient::ExceptionWithResponse => e
    puts "Error during upload session finalization: #{e.response}"
  end

  # Poll the upload session status
  def monitor_upload_progress(session_id)
    url = "https://#{@server}/Panopto/PublicAPI/REST/sessionUpload/#{session_id}"

    while true
      response = RestClient.get(url, { Authorization: "Bearer #{@access_token}" })
      session_status = JSON.parse(response.body)

      puts "Current status: #{session_status['State']}"

      if session_status['State'] == 4  # 4 means the session is complete
        puts "Upload complete!"
        break
      end

      sleep(5)
    end
  rescue RestClient::ExceptionWithResponse => e
    puts "Error checking session progress: #{e.response}"
  end
end
