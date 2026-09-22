# frozen_string_literal: true

require 'test_helper'
require 'zip'
require 'spreadsheet'

class SpreadsheetUploadPolicyTest < ActiveSupport::TestCase
  def with_xlsx(extra = {})
    entries = {
      '[Content_Types].xml' => '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>',
      '_rels/.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml' => '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheets/></workbook>'
    }.merge(extra)
    Tempfile.create(['sheet', '.xlsx']) do |file|
      file.close
      Zip::File.open(file.path, Zip::File::CREATE) do |zip|
        entries.each { |name, bytes| zip.get_output_stream(name) { |stream| stream.write(bytes) } }
      end
      File.open(file.path) { |handle| yield({ filename: 'sheet.XLSX', 'tempfile' => handle }) }
    end
  end

  test 'real XLSX structure accepted for task and chat without altering bytes' do
    with_xlsx do |file|
      before = File.binread(file['tempfile'].path)
      %w[csv comment_attachment].each do |kind|
        result = FileHelper.accept_file(file, 'Spreadsheet', kind)
        assert result[:accepted], result[:msg]
      end
      assert_equal before, File.binread(file['tempfile'].path)
    end
  end

  test 'Office macro embedded malformed external and traversal payloads are rejected' do
    [
      { 'xl/vbaProject.bin' => 'macro' },
      { 'xl/embeddings/oleObject1.bin' => 'object' },
      { 'xl/connections.xml' => '<connections><connection refreshOnLoad="1"><webPr url="https://example.invalid"/></connection></connections>' },
      { 'xl/externalLinks/externalLink1.xml' => '<externalLink><ddeLink ddeService="test"/></externalLink>' },
      { 'xl/queryTables/queryTable1.xml' => '<queryTable/>' },
      { '../escape' => 'bad' },
      { 'xl/workbook.xml' => '<not-a-workbook>' },
      { 'xl/_rels/workbook.xml.rels' => '<Relationships><Relationship TargetMode="External" Type="externalLink" Target="https://example.invalid/private"/></Relationships>' }
    ].each do |extra|
      with_xlsx(extra) do |file|
        result = FileHelper.accept_file(file, 'Spreadsheet', 'comment_attachment')
        assert_not result[:accepted], extra.keys.inspect
        assert_equal 'UPLOAD_CORRUPT', result[:code]
      end
    end
  end

  test 'legacy XLS remains a task-only spreadsheet and must contain readable workbook records' do
    Tempfile.create(['legacy', '.xls']) do |file|
      workbook = Spreadsheet::Workbook.new
      workbook.create_worksheet(name: 'Results').row(0).push('Name', 7)
      workbook.write(file.path)
      upload = { filename: 'legacy.xls', 'tempfile' => file }
      result = FileHelper.accept_file(upload, 'Spreadsheet', 'csv')
      assert result[:accepted], result[:msg]
      assert_not FileHelper.accept_file(upload, 'Spreadsheet', 'comment_attachment')[:accepted]
    end
  end

  test 'csv requirement persists and spreadsheet originals are retained in the submission archive' do
    project = FactoryBot.create(:project)
    definition = project.unit.task_definitions.first
    definition.update!(upload_requirements: [{ 'key' => 'file0', 'name' => 'Results', 'type' => 'csv' }])
    task = project.task_for_task_definition(definition)
    assert_equal 'csv', definition.reload.upload_requirements.first['type']
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, '000-csv.csv'), "a,b\n1,2\n")
      destination = File.join(directory, 'originals.zip')
      assert task.compress_new_to_done(task_dir: "#{directory}/", zip_file_path: destination, rm_task_dir: false)
      Zip::File.open(destination) do |zip|
        assert_equal "a,b\n1,2\n", zip.read("#{task.id}/000-csv.csv")
      end
    end
    definition.upload_requirements.first['type'] = 'arbitrary'
    assert_not definition.valid?
  end
  test 'the existing Code extensions remain accepted but a renamed document is not Code' do
    Tempfile.create(['source', '.py']) do |file|
      file.write("print('hello')\n")
      file.flush
      assert FileHelper.accept_file({ filename: 'main.py', 'tempfile' => file }, 'Code', 'code')[:accepted]
      assert_not FileHelper.accept_file({ filename: 'main.pdf', 'tempfile' => file }, 'Code', 'code')[:accepted]
    end
  end

end
