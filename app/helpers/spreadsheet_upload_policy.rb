# frozen_string_literal: true

require 'ole/storage'

# Spreadsheet task files stay in their original format and are download-only.
# Chat deliberately excludes legacy XLS; task definitions retain the csv key.
module SpreadsheetUploadPolicy
  def self.validate(file)
    extension = File.extname(file['filename'] || file[:filename]).downcase
    path = file['tempfile'].path
    max_size = Doubtfire::Application.config.max_file_size.to_i
    max_size = 10_000_000 if max_size <= 0
    unless File.size?(path) && File.size(path) <= max_size
      FileHelper.log_file_rejection('Spreadsheet size check failed', 'csv', file)
      return { accepted: false, msg: "Spreadsheet must not be empty or exceed #{max_size / 1_000_000}MB." }
    end
    detected = MimeCheckHelpers.mime_type(path).split(';').first
    valid = case extension
            when '.csv'
              %w[text/csv application/csv text/plain].include?(detected) && CommentAttachmentPolicy.validate_csv(path)[:valid]
            when '.xlsx'
              %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/zip].include?(detected) && FileHelper.validate_docx(path, format: 'xlsx')[:valid]
            when '.xls'
              %w[application/vnd.ms-excel application/x-ole-storage application/CDFV2].include?(detected) && valid_legacy_workbook?(path)
            else false
            end
    FileHelper.log_file_rejection('Spreadsheet format check failed', 'csv', file) unless valid
    { accepted: valid == true, msg: valid ? 'success' : 'Choose a valid, unencrypted CSV, XLS or XLSX spreadsheet without macros or embedded objects.' }
  rescue StandardError
    FileHelper.log_file_rejection('Spreadsheet validation failed', 'csv', file)
    { accepted: false, msg: 'The spreadsheet could not be read. Save it as an unencrypted CSV or XLSX and try again.' }
  end

  def self.valid_legacy_workbook?(path)
    Ole::Storage.open(path) do |storage|
      names = storage.dir.entries('/') - %w[. ..]
      return false unless (names - ["Workbook", "Book", "\u0005SummaryInformation", "\u0005DocumentSummaryInformation"]).empty?
      name = (names & %w[Workbook Book]).first
      return false unless name

      storage.file.open(name) do |stream|
        while (header = stream.read(4)) && !header.empty?
          return false unless header.bytesize == 4
          record, size = header.unpack('vv')
          data = stream.read(size)
          return false unless data && data.bytesize == size
          return false if record == 0x01ae && (data.bytesize < 4 || data.unpack('vv')[1] != 0x0401) # external workbook / DDE
          return false if [0x002f, 0x00d3].include?(record) # encryption / VBA project
          return false if record == 0x0085 && ![0, 2].include?(data.getbyte(5)) # macro / VB sheets
          return false if record == 0x0809 && data.bytesize >= 4 && data.unpack('vv')[1] == 0x0040
        end
      end
    end
    workbook = Roo::Spreadsheet.open(path, extension: :xls)
    workbook.sheets.any?
  ensure
    workbook&.close if workbook.respond_to?(:close)
  end
end
