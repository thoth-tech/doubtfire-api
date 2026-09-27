# frozen_string_literal: true

# Keep this test outside test/helpers: test_helper requires every helper file
# into every test process, which would execute this test in multiple shards.

require 'test_helper'
require 'zip'

class Batch03DocxFileHelperTest < ActiveSupport::TestCase
  DOCX_MAIN_CONTENT_TYPE =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml'

  def with_docx(entries)
    Tempfile.create(['batch03-docx', '.docx']) do |tempfile|
      tempfile.close

      Zip::File.open(tempfile.path, Zip::File::CREATE) do |zip|
        entries.each do |name, content|
          zip.get_output_stream(name) { |stream| stream.write(content) }
        end
      end

      yield tempfile.path
    end
  end

  def minimal_docx_entries(content_type: DOCX_MAIN_CONTENT_TYPE)
    {
      '[Content_Types].xml' => <<~XML,
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Override PartName="/word/document.xml" ContentType="#{content_type}"/>
        </Types>
      XML
      '_rels/.rels' => <<~XML,
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
      XML
      'word/document.xml' => <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>Batch 03</w:t></w:r></w:p></w:body>
        </w:document>
      XML
    }
  end

  test 'strictly accepts a valid uppercase DOCX as a word document' do
    path = Rails.root.join('test_files/TestWordDoc.docx')

    result = File.open(path, 'rb') do |file|
      FileHelper.accept_file(
        { filename: 'phone-evidence.DOCX', 'tempfile' => file },
        'Batch 03 DOCX',
        'word_document'
      )
    end

    assert result[:accepted], result[:msg]
    assert_equal 'success', result[:msg]
  end

  test 'rejects DOCX bytes when the extension does not identify a word document' do
    path = Rails.root.join('test_files/TestWordDoc.docx')

    result = File.open(path, 'rb') do |file|
      FileHelper.accept_file(
        { filename: 'phone-evidence.pdf', 'tempfile' => file },
        'Batch 03 mismatched DOCX',
        'word_document'
      )
    end

    assert_not result[:accepted]
    assert_equal 'invalid file extension.', result[:msg]
  end

  test 'rejects non-DOCX bytes carrying a DOCX extension' do
    path = Rails.root.join('test_files/submissions/00_question.pdf')

    result = File.open(path, 'rb') do |file|
      FileHelper.accept_file(
        { filename: 'disguised.DOCX', 'tempfile' => file },
        'Batch 03 mismatched PDF',
        'word_document'
      )
    end

    assert_not result[:accepted]
    assert_match(/MIME type|corrupt|OOXML/i, result[:msg])
  end

  test 'rejects a corrupt file presented as DOCX' do
    Tempfile.create(['batch03-corrupt', '.docx']) do |tempfile|
      tempfile.binmode
      tempfile.write("PK\x03\x04not-a-complete-zip")
      tempfile.flush

      result = FileHelper.validate_docx(tempfile.path)

      assert_not result[:valid]
      assert_match(/corrupt|valid OOXML/i, result[:msg])
    end
  end

  test 'rejects a DOCX package missing a required OOXML part' do
    entries = minimal_docx_entries
    entries.delete('word/document.xml')

    with_docx(entries) do |path|
      result = FileHelper.validate_docx(path)

      assert_not result[:valid]
      assert_match(%r{missing word/document\.xml}i, result[:msg])
    end
  end

  test 'rejects a DOCX package with an invalid main OOXML content type' do
    with_docx(minimal_docx_entries(content_type: 'application/xml')) do |path|
      result = FileHelper.validate_docx(path)

      assert_not result[:valid]
      assert_match(/invalid main document content type/i, result[:msg])
    end
  end

  test 'rejects a DOCX package containing a traversal entry' do
    entries = minimal_docx_entries.merge('../../../escape.txt' => 'must not escape')

    with_docx(entries) do |path|
      result = FileHelper.validate_docx(path)

      assert_not result[:valid]
      assert_match(/unsafe path/i, result[:msg])
    end
  end

  test 'rejects a DOCX package containing a nested archive' do
    entries = minimal_docx_entries.merge('word/embeddings/payload.zip' => "PK\x03\x04nested")

    with_docx(entries) do |path|
      result = FileHelper.validate_docx(path)

      assert_not result[:valid]
      assert_match(/nested archives/i, result[:msg])
    end
  end

  test 'safe upload filename bounds long Unicode and removes path and control material' do
    raw_name = "../../private/<evidence>#{'📱測' * 180}\r\nInjected: yes.DOCX"

    safe_name = FileHelper.safe_upload_filename({ 'filename' => raw_name })

    assert_operator safe_name.length, :<=, 255
    assert_equal '.DOCX', File.extname(safe_name)
    assert_not_includes safe_name, '/'
    assert_not_includes safe_name, '\\'
    assert_not_includes safe_name, '..'
    assert_equal safe_name.gsub(/[[:cntrl:]]/, ''), safe_name
    assert_includes safe_name, '<evidence>'
    assert_includes safe_name, '📱'
  end

  test 'rejects a DOCX whose main part has the wrong type even when the right type appears elsewhere' do
    entries = minimal_docx_entries(content_type: 'application/xml')
    entries['[Content_Types].xml'] = entries['[Content_Types].xml'].sub(
      '</Types>',
      "<!-- #{DOCX_MAIN_CONTENT_TYPE} --></Types>"
    )

    with_docx(entries) do |path|
      result = FileHelper.validate_docx(path)

      assert_not result[:valid]
      assert_match(/invalid main document content type/i, result[:msg])
    end
  end
end
