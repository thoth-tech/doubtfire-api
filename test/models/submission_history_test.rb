require 'test_helper'
require 'tmpdir'
require 'zip'
require 'spreadsheet'

class SubmissionHistoryTest < ActiveSupport::TestCase
  def test_creates_archive_with_only_selected_upload_requirements
    unit = FactoryBot.create(:unit, task_count: 1)
    task = unit.active_projects.first.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(
      assessment_enabled: false,
      upload_requirements: [
        { 'key' => 'file0', 'name' => 'main.rb', 'type' => 'code', 'submission_history' => true },
        { 'key' => 'file1', 'name' => 'report.pdf', 'type' => 'document', 'submission_history' => false }
      ]
    )

    Dir.mktmpdir do |dir|
      source_path = File.join(dir, 'done.zip')
      output_path = File.join(dir, 'history')
      create_source_archive(source_path, task.id)

      with_file_helper_methods(
        zip_file_path_for_done_task: source_path,
        task_submission_identifier_path: output_path
      ) do
        history = SubmissionHistory.create_archive!(task, '12345')

        assert history.persisted?
        Zip::File.open(history.archive_file_name) do |archive|
          assert archive.find_entry("12345/#{task.id}/000-code.rb")
          assert_nil archive.find_entry("12345/#{task.id}/001-document.pdf")
        end

        Zip::File.open_buffer(StringIO.new(history.submission_zip_data)) do |download|
          assert download.find_entry("#{task.id}/000-code.rb")
          assert_nil download.find_entry("#{task.id}/001-document.pdf")
        end
      end
    end
  end

  def test_retains_spreadsheet_originals_alongside_existing_selected_types
    unit = FactoryBot.create(:unit, task_count: 1, student_count: 1)
    task = unit.active_projects.first.task_for_task_definition(unit.task_definitions.first)
    kinds = %w[csv csv csv code document image zip archive csv]
    task.task_definition.update!(
      assessment_enabled: false,
      upload_requirements: kinds.each_with_index.map do |kind, index|
        { 'key' => "file#{index}", 'name' => "Evidence #{index}", 'type' => kind, 'submission_history' => index != 8 }
      end
    )

    legacy_workbook = Spreadsheet::Workbook.new
    legacy_workbook.create_worksheet(name: 'Results').row(0).push('Name', 7)
    legacy_bytes = StringIO.new(''.b)
    legacy_workbook.write(legacy_bytes)
    originals = {
      '000-csv.csv' => "Name,Value\r\nCafé,7\r\n".b,
      '001-csv.xlsx' => File.binread(Rails.root.join('test_files/csv_test_files/COS10001-Tasks.xlsx')),
      '002-csv.xls' => legacy_bytes.string,
      '003-code.rb' => 'puts "retained"',
      '004-document.pdf' => '%PDF-original',
      '005-image.png' => "\x89PNG\r\n".b,
      '006-zip.zip' => 'original zip bytes',
      '007-archive.zip' => 'original archive bytes'
    }

    Dir.mktmpdir do |dir|
      source_path = File.join(dir, 'done.zip')
      Zip::File.open(source_path, create: true) do |archive|
        originals.merge('008-csv.csv' => 'not selected', 'metadata.json' => '{}').each do |name, bytes|
          archive.get_output_stream("#{task.id}/#{name}") { |output| output.write(bytes) }
        end
      end
      with_file_helper_methods(
        zip_file_path_for_done_task: source_path,
        task_submission_identifier_path: File.join(dir, 'history')
      ) do
        history = SubmissionHistory.create_archive!(task, '54321')
        assert history.has_submission_files?
        Zip::File.open(history.archive_file_name) do |archive|
          assert_equal originals.length, archive.entries.length
          originals.each do |name, bytes|
            assert_equal bytes, archive.read("54321/#{task.id}/#{name}").b
          end
        end
        Zip::File.open_buffer(StringIO.new(history.submission_zip_data)) do |download|
          assert_equal originals.length, download.entries.length
          originals.each do |name, bytes|
            assert_equal bytes, download.read("#{task.id}/#{name}").b
          end
          assert_nil download.find_entry("#{task.id}/008-csv.csv")
          assert_nil download.find_entry("#{task.id}/metadata.json")
        end
      end
    end
  end

  def test_does_not_create_record_when_archive_copy_fails
    unit = FactoryBot.create(:unit, task_count: 1)
    task = unit.active_projects.first.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(
      assessment_enabled: false,
      upload_requirements: [
        { 'key' => 'file0', 'name' => 'main.rb', 'type' => 'code', 'submission_history' => true }
      ]
    )

    assert_no_difference('SubmissionHistory.count') do
      assert_raises(RuntimeError) do
        with_file_helper_methods(zip_file_path_for_done_task: '/missing/submission.zip') do
          SubmissionHistory.create_archive!(task, '12345')
        end
      end
    end
  end

  def test_keeps_multiple_timestamps_in_one_task_archive
    unit = FactoryBot.create(:unit, task_count: 1)
    task = unit.active_projects.first.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(
      assessment_enabled: false,
      upload_requirements: [
        { 'key' => 'file0', 'name' => 'main.rb', 'type' => 'code', 'submission_history' => true }
      ]
    )

    Dir.mktmpdir do |dir|
      source_path = File.join(dir, 'done.zip')
      output_path = File.join(dir, 'history')
      create_source_archive(source_path, task.id)

      with_file_helper_methods(
        zip_file_path_for_done_task: source_path,
        task_submission_identifier_path: output_path
      ) do
        first = SubmissionHistory.create_archive!(task, '12345')
        SubmissionHistory.create_archive!(task, '67890')

        Zip::File.open(first.archive_file_name) do |archive|
          assert archive.find_entry("12345/#{task.id}/000-code.rb")
          assert archive.find_entry("67890/#{task.id}/000-code.rb")
        end

        first.destroy!

        Zip::File.open(File.join(output_path, 'history.zip')) do |archive|
          assert_nil archive.find_entry("12345/#{task.id}/000-code.rb")
          assert archive.find_entry("67890/#{task.id}/000-code.rb")
        end
      end
    end
  end

  private

  def create_source_archive(path, task_id)
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream("#{task_id}/000-code.rb") { |file| file.write('puts "hello"') }
      zip.get_output_stream("#{task_id}/001-document.pdf") { |file| file.write('%PDF') }
    end
  end

  def with_file_helper_methods(replacements)
    originals = replacements.to_h { |name, _value| [name, FileHelper.method(name)] }
    replacements.each do |name, value|
      FileHelper.define_singleton_method(name) { |*_args| value }
    end

    yield
  ensure
    originals&.each do |name, implementation|
      FileHelper.define_singleton_method(name, implementation)
    end
  end
end
