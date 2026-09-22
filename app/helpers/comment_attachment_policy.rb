# frozen_string_literal: true

# Shared by the authenticated policy response, validation and storage dispatch.
# A category never authorises an arbitrary MIME type or filename extension.
module CommentAttachmentPolicy
  MAX_BYTES = 30_000_000 # Exclusive, matching the existing comment API.
  MAX_SELECTION_COUNT = 5
  CATEGORIES = [
    { id: 'pdf', name: 'PDF', extensions: %w[pdf], mime_types: %w[application/pdf], preview: 'pdf' },
    { id: 'document', name: 'Document', extensions: %w[docx], mime_types: [FileHelper::DOCX_MIME_TYPE], preview: 'download' },
    { id: 'spreadsheet', name: 'Spreadsheet', extensions: %w[csv xlsx], mime_types: %w[text/csv application/csv text/plain application/vnd.openxmlformats-officedocument.spreadsheetml.sheet], preview: 'download' },
    { id: 'image', name: 'Image', extensions: %w[png bmp tiff tif jpeg jpg gif], mime_types: %w[image/png image/bmp image/x-ms-bmp image/tiff image/jpeg image/gif], preview: 'image' },
    { id: 'audio', name: 'Audio', extensions: %w[wav ogg mp3 mp4 webm aac pcm aiff flac wma alac], mime_types: %w[audio/ video/webm application/ogg], preview: 'audio' }
  ].freeze

  def self.category(filename)
    extension = File.extname(filename.to_s).downcase.delete_prefix('.')
    CATEGORIES.find { |item| item[:extensions].include?(extension) }
  end

  def self.public_policy
    {
      version: 1,
      max_bytes_exclusive: MAX_BYTES,
      max_selection_count: MAX_SELECTION_COUNT,
      categories: CATEGORIES.map { |item| item.except(:mime_types) }
    }
  end

  def self.validate(file)
    path = file['tempfile'].path
    filename = file['filename'] || file[:filename]
    category = category(filename)
    # MediaRecorder sends a Blob with the browser's default extensionless name.
    category ||= CATEGORIES.find { |item| item[:id] == 'audio' } if filename == 'blob'
    return rejected('UPLOAD_EMPTY', 'Attachment is empty.', file) unless File.size?(path)
    return rejected('UPLOAD_TOO_LARGE', 'Attachment must be smaller than 30 MB.', file) if File.size(path) >= MAX_BYTES
    return rejected('UPLOAD_EXTENSION_NOT_ALLOWED', 'Unsupported attachment format. Choose a format listed beside Attach a file.', file) unless category

    extension = File.extname(filename).downcase.delete_prefix('.')
    detected = MimeCheckHelpers.mime_type(path).split(';').first
    permitted_mimes = case extension
                      when 'pcm' then %w[audio/L16 audio/x-pcm application/octet-stream]
                      when 'csv' then %w[text/csv application/csv text/plain]
                      when 'xlsx' then %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/zip]
                      else category[:mime_types]
                      end
    return rejected('UPLOAD_MIME_INVALID', 'File contents do not match the selected format.', file) unless permitted_mimes.any? { |mime| detected == mime || (mime.end_with?('/') && detected.start_with?(mime)) }

    result = case extension
             when 'docx' then FileHelper.validate_docx(path, max_file_size: MAX_BYTES - 1)
             when 'xlsx' then FileHelper.validate_docx(path, format: 'xlsx', max_file_size: MAX_BYTES - 1)
             when 'pdf' then FileHelper.validate_pdf(path)
             when 'csv' then validate_csv(path)
             else { valid: true }
             end
    return rejected(result[:encrypted] ? 'UPLOAD_ENCRYPTED' : 'UPLOAD_CORRUPT', 'The attachment is malformed, encrypted or contains unsupported active content.', file) if !result[:valid] || result[:encrypted]

    Rails.logger.debug('Uploaded file is accepted')
    { accepted: true, msg: 'success', category: category[:id] }
  end

  def self.validate_csv(path)
    # Stream records so a near-limit CSV does not build a second in-memory table.
    CSV.foreach(path, encoding: 'bom|utf-8') { |row| return { valid: false } if row.any? { |cell| cell&.include?("\0") } }
    { valid: true }
  rescue CSV::MalformedCSVError, EncodingError, ArgumentError
    { valid: false }
  end

  def self.rejected(code, message, file)
    reason = { 'UPLOAD_EXTENSION_NOT_ALLOWED' => 'File extension check failed', 'UPLOAD_MIME_INVALID' => 'File MIME check failed' }.fetch(code, 'Upload rejected')
    FileHelper.log_file_rejection(reason, 'comment_attachment', file, code: code)
    { accepted: false, code: code, msg: message }
  end
end
