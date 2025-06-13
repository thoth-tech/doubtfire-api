require 'test_helper'

class FileHelperTest < ActiveSupport::TestCase
  test 'sanitize_pdf should sanitize a valid PDF' do
    input_path = 'test/fixtures/files/valid.pdf'
    output_path = File.join(Dir.tmpdir, 'sanitized-valid.pdf')

    result = FileHelper.sanitize_pdf(input_path, output_path)
    assert result[:success], "Expected sanitization to succeed, but got: #{result[:msg]}"
    assert File.exist?(result[:sanitized_path]), 'Sanitized file does not exist'
  end

  test 'sanitize_pdf should fail for an invalid PDF' do
    input_path = 'test/fixtures/files/invalid.pdf'

    result = FileHelper.sanitize_pdf(input_path)
    assert_not result[:success], 'Expected sanitization to fail for invalid PDF'
  end
end
