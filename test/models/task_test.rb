require 'test_helper'
require 'pdf-reader'

#
# Contains tests for Task model objects - not accessed via API
#
class TaskDefinitionTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::TestFileHelper
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def error!(msg, _code)
    raise StandardError, msg
  end

  def clear_submission(task)
    FileUtils.rm_rf(FileHelper.student_work_dir(:new, task, false))
    FileUtils.rm_rf(FileHelper.student_work_dir(:in_process, task, false))
  end

  def app
    Rails.application
  end

  def test_comments_for_user
    project = FactoryBot.create(:project)
    unit = project.unit
    user = project.student
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)

    task.add_text_comment(convenor, 'Hello World')
    task.add_text_comment(convenor, 'Message 2')
    task.add_text_comment(convenor, 'Last message')

    comments = task.comments_for_user(user)
    comments.each do |data|
      assert_equal 1, data.is_new
    end

    task.mark_comments_as_read user, task.comments

    comments = task.comments_for_user(user)
    comments.each do |data|
      assert_equal 0, data.is_new
    end
  end

  def test_pdf_creation_with_gif
    unit = Unit.first
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with image',
        description: 'img task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'TaskPdfWithGif',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'An Image', "type" => 'image' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/unbelievable.gif', 'image/gif', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    td.destroy
    assert_not File.exist? path
  end

  def test_image_upload
    unit = Unit.first
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with image2',
        description: 'img task2',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'TaskPdfWithGif2',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'An Image', "type" => 'image' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/unbelievable.gif', 'image/gif', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status

    task = project.task_for_task_definition(td)
    task.move_files_to_in_process(FileHelper.student_work_dir(:new))

    assert File.exist? "#{Doubtfire::Application.config.student_work_dir}/in_process/#{task.id}/000-image.jpg"

    td.destroy
  end

  def test_pdf_creation_with_jpg
    unit = Unit.first
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with image',
        description: 'img task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'TaskPdfWithJpg',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'An Image', "type" => 'image' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/Swinburne.jpg', 'image/jpg', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status

    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    td.destroy
    assert_not File.exist? path
  end

  def test_pdf_with_quotes_in_task_title
    unit = Unit.first
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: '"Quoted Task"',
        description: 'Task with quotes in name',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'TaskQuoted',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'An Image', "type" => 'image' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/Swinburne.jpg', 'image/jpg', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    task = project.task_for_task_definition(td)

    task.convert_submission_to_pdf(log_to_stdout: false)

    path = task.final_pdf_path
    assert File.exist? path

    td.destroy
    assert_not File.exist? path
  end

  def test_copy_draft_learning_summary
    unit = FactoryBot.create :unit, student_count:1, task_count:0
    task_def = FactoryBot.create(:task_definition, unit: unit, upload_requirements: [{'key' => 'file0','name' => 'Draft learning summary','type' => 'document'}])

    # Maybe make this call API to set
    unit.draft_task_definition = task_def
    unit.save

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    project = unit.active_projects.first

    # Check we can't auto generate if we do not have a learning summary report
    refute project.learning_summary_report_exists?
    refute project.auto_generate_portfolio
    refute project.compile_portfolio
    refute project.portfolio_auto_generated

    path = File.join(project.portfolio_temp_path, '000-document-LearningSummaryReport.pdf')
    refute File.exist? path

    data_to_post = with_file('test_files/unit_files/sample-learning-summary.pdf', 'application/pdf', data_to_post)

    add_auth_header_for user: project.user

    post "/api/projects/#{project.id}/task_def_id/#{task_def.id}/submission", data_to_post

    assert_equal 201, last_response.status

    project_task = project.task_for_task_definition(task_def)

    # Check if file exists in :new
    assert project_task.processing_pdf?

    # Generate pdf for task
    assert project_task.convert_submission_to_pdf(log_to_stdout: false)

    # Check if pdf was copied over
    project.reload
    assert project.uses_draft_learning_summary
    assert File.exist? path
    assert project.learning_summary_report_exists?

    # Check we can auto generate
    project.auto_generate_portfolio
    assert project.compile_portfolio
    assert project.portfolio_auto_generated

    project.compile_portfolio = false
    project.portfolio_auto_generated = false
    project.save

    # Check auto generate doesn't work if we are not enrolled
    project.enrolled = false
    refute project.auto_generate_portfolio
    refute project.compile_portfolio
    refute project.portfolio_auto_generated

    unit.destroy
    assert_not File.exist? path
  end

  def test_draft_learning_summary_wont_copy
    unit = FactoryBot.create :unit, student_count:1, task_count:0
    task_def = FactoryBot.create(:task_definition, unit: unit, upload_requirements: [{'key' => 'file0','name' => 'Draft learning summary','type' => 'document'}])

    unit.draft_task_definition = task_def

    project = unit.active_projects.first

    path = File.join(project.portfolio_temp_path, '000-document-LearningSummaryReport.pdf')
    FileUtils.mkdir_p(project.portfolio_temp_path)

    FileUtils.cp Rails.root.join('test_files/unit_files/sample-learning-summary.pdf'), path
    assert File.exist? path

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/unit_files/sample-learning-summary.pdf', 'application/pdf', data_to_post)

    add_auth_header_for user: project.user

    post "/api/projects/#{project.id}/task_def_id/#{task_def.id}/submission", data_to_post

    project_task = project.task_for_task_definition(task_def)

    # Check if file exists in :new
    assert project_task.processing_pdf?

    # Generate pdf for task
    assert project_task.convert_submission_to_pdf(log_to_stdout: false)

    # Check if the file was moved to portfolio
    assert_not project.uses_draft_learning_summary

    unit.destroy
    assert_not File.exist? path
  end

  def test_ipynb_to_pdf
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with ipynb',
        description: 'Code task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'TaskPdfWithIpynb',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'A notebook', "type" => 'code' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/vectorial_graph.ipynb', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # Test if latex math was rendered properly
    reader = PDF::Reader.new(task.final_pdf_path)

    # PDF-reader incorrectly parses "weight (kg) / height (m)^2" as "weight (2g) / height (m)", misplacing the ^2
    # Detecting "height" and "weight" confirms correct LaTeX rendering
    assert reader.pages.last.text.include?("BMI: bmi ="), reader.pages.last.text
    assert reader.pages.last.text.include?("weight")
    assert reader.pages.last.text.include?("height (m)")

    # ensure the notice is not included when the notebook doesn't have long lines source code cells
    # and no errors
    reader.pages.each do |page|
      assert_not page.text.include? 'The rest of this line has been truncated by the system to improve readability.'
      assert_not page.text.include?('ERROR when parsing'), page.text
    end

    # test line wrapping in jupynotex
    data_to_post = with_file('test_files/submissions/long.ipynb', 'application/json', data_to_post)

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is included when the notebook has long line in source code cells
    reader = PDF::Reader.new(task.final_pdf_path)
    assert reader.pages[1].text.gsub(/\s+/, " ").include? "[The rest of this line has been truncated by the system to improve readability.]"

    # test excessive long raw data
    data_to_post = with_file('test_files/submissions/many_lines.ipynb', 'application/json', data_to_post)
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is included when the notebook has long line in source code cells
    reader = PDF::Reader.new(task.final_pdf_path)

    assert_equal 4, reader.pages.count

    td.destroy
    assert_not File.exist? path
    unit.destroy!
  end

  def test_code_submission_with_long_lines
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with super ling lines in code submission',
        description: 'Code task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'Long',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'long.py', "type" => 'code' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/long.py', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is included when rendered files are truncated
    reader = PDF::Reader.new(task.final_pdf_path)
    assert reader.pages[1].text.include? "This file has additional line breaks applied"

    # submit a normal file and ensure the notice is not included in the PDF
    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/normal.py', 'application/json', data_to_post)
    project = unit.active_projects.first
    add_auth_header_for user: unit.main_convenor_user
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post
    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is not included
    reader = PDF::Reader.new(task.final_pdf_path)
    assert_not reader.pages[1].text.include? "This file has additional line breaks applied"

    td.destroy
    assert_not File.exist? path
    unit.destroy!
  end

  def test_code_submission_with_long_lines
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with super ling lines in code submission',
        description: 'Code task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'Long',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'long.py', "type" => 'code' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/long.py', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is included when rendered files are truncated
    reader = PDF::Reader.new(task.final_pdf_path)
    assert reader.pages[1].text.include? "This file has additional line breaks applied"

    # submit a normal file and ensure the notice is not included in the PDF
    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/normal.py', 'application/json', data_to_post)
    project = unit.active_projects.first
    add_auth_header_for user: unit.main_convenor_user
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post
    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is not included
    reader = PDF::Reader.new(task.final_pdf_path)
    assert_not reader.pages[1].text.include? "This file has additional line breaks applied"

    td.destroy
    assert_not File.exist? path
    unit.destroy!
  end

  def test_code_submission_with_long_lines
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'Task with super ling lines in code submission',
        description: 'Code task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'Long',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'long.py', "type" => 'code' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/long.py', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is included when rendered files are truncated
    reader = PDF::Reader.new(task.final_pdf_path)
    assert reader.pages[1].text.include? "This file has additional line breaks applied"

    # submit a normal file and ensure the notice is not included in the PDF
    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    data_to_post = with_file('test_files/submissions/normal.py', 'application/json', data_to_post)
    project = unit.active_projects.first
    add_auth_header_for user: unit.main_convenor_user
    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post
    assert_equal 201, last_response.status, last_response_body

    # test submission generation
    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    # ensure the notice is not included
    reader = PDF::Reader.new(task.final_pdf_path)
    assert_not reader.pages[1].text.include? "This file has additional line breaks applied"

    td.destroy
    assert_not File.exist? path
    unit.destroy!
  end

  def test_pdf_validation_on_submit
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'PDF Test Task',
        description: 'Test task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'PDFTestTask',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'A pdf file', "type" => 'document' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    # submit an encrypted (but valid) PDF file and ensure it's rejected immediately
    data_to_post = with_file('test_files/submissions/encrypted.pdf', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 403, last_response.status, last_response_body

    # submit a corrupted PDF file and ensure it's rejected immediately
    data_to_post = with_file('test_files/submissions/corrupted.pdf', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 403, last_response.status, last_response_body

    # submit a valid PDF file and ensure it's accepted
    data_to_post = with_file('test_files/submissions/valid.pdf', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    task = project.task_for_task_definition(td)
    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    td.destroy
    assert_not File.exist? path
    unit.destroy!
  end

  def test_pdf_creation_fails_on_invalid_pdf
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'PDF Test Task',
        description: 'Test task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'PDFTestTask',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'A pdf file', "type" => 'code' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    project = unit.active_projects.first

    task = project.task_for_task_definition(td)

    folder = FileHelper.student_work_dir(:new, task)

    # Copy the file in
    FileUtils.cp(Rails.root.join('test_files/submissions/corrupted.pdf'), "#{folder}/001-code.cs")

    begin
      assert_not task.convert_submission_to_pdf(log_to_stdout: false)
    rescue StandardError => e
      task.reload

      assert_equal 2, task.comments.count
      assert task.comments.last.comment.starts_with?('**Automated Comment**:')
      assert task.comments.last.comment.include?(e.message.to_s)

      td.destroy
      unit.destroy!
    end
  end

  def test_pax_crash_does_not_stop_pdf_creation
    unit = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    td = TaskDefinition.new({
        unit_id: unit.id,
        tutorial_stream: unit.tutorial_streams.first,
        name: 'PDF Test Task',
        description: 'Test task',
        weighting: 4,
        target_grade: 0,
        start_date: unit.start_date + 1.week,
        target_date: unit.start_date + 2.weeks,
        abbreviation: 'PDFTestTask',
        restrict_status_updates: false,
        upload_requirements: [ { "key" => 'file0', "name" => 'A pdf file', "type" => 'document' } ],
        plagiarism_warn_pct: 0.8,
        is_graded: false,
        max_quality_pts: 0
      })
    td.save!

    data_to_post = {
      trigger: 'ready_for_feedback'
    }

    # submit an encrypted (but valid) PDF file and ensure it's rejected immediately
    data_to_post = with_file('test_files/submissions/valid.pdf', 'application/json', data_to_post)

    project = unit.active_projects.first

    add_auth_header_for user: unit.main_convenor_user

    post "/api/projects/#{project.id}/task_def_id/#{td.id}/submission", data_to_post

    assert_equal 201, last_response.status, last_response_body

    task = project.task_for_task_definition(td)

    rails_latex_path = Rails.root.join("tmp/rails-latex/#{Process.pid}-#{Thread.current.hash}")
    FileUtils.mkdir_p(rails_latex_path)
    FileUtils.cp(Rails.root.join('test_files/latex/input-broken.aux'), "#{rails_latex_path}/input.aux")

    assert task.convert_submission_to_pdf(log_to_stdout: false)
    path = task.zip_file_path_for_done_task
    assert path
    assert File.exist? path
    assert File.exist? task.final_pdf_path

    td.destroy
    assert_not File.exist? path
    unit.destroy!
  end

  def test_accept_files_checks_they_all_exist
    project = FactoryBot.create(:project)
    unit = project.unit
    user = project.student
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first

    task_definition.upload_requirements = [
      {
        "key" => 'file0',
        "name" => 'Document 1',
        "type" => 'document'
      },
      {
        "key" => 'file1',
        "name" => 'Document 2',
        "type" => 'document'
      },
      {
        "key" => 'file2',
        "name" => 'Code 1',
        "type" => 'code'
      },
      {
        "key" => 'file3',
        "name" => 'Document 3',
        "type" => 'document'
      },
      {
        "key" => 'file4',
        "name" => 'Document 4',
        "type" => 'document'
      }
    ]

    # Saving task def
    task_definition.save!

    # Test that the task def is setup correctly
    assert_equal 5, task_definition.number_of_uploaded_files

    # Now... lets upload a submission
    task = project.task_for_task_definition(task_definition)

    # Create a submission - but no files!
    begin
      task.accept_submission user, [], self, nil, 'ready_for_feedback', nil
      assert false, 'Should have raised an error with no files submitted'
    rescue StandardError => e
      assert_equal :not_started, task.status
    end

    # Create a submission
    task.accept_submission user, [
      {
        id: 'file0',
        name: 'Document 1',
        type: 'document',
        filename: 'file0.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      },
      {
        id: 'file1',
        name: 'Document 2',
        type: 'document',
        filename: 'file1.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      },
      {
        id: 'file2',
        name: 'Code 1',
        type: 'code',
        filename: 'code.cs',
        "tempfile" => File.new(test_file_path('submissions/program.cs'))
      },
      {
        id: 'file3',
        name: 'Document 3',
        type: 'document',
        filename: 'file3.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      },
      {
        id: 'file4',
        name: 'Document 4',
        type: 'document',
        filename: 'file4.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      }
    ], self, nil, 'ready_for_feedback', nil, accepted_tii_eula: true

    assert_equal :ready_for_feedback, task.status

    task_definition.upload_requirements = []
    task_definition.save!

    task.task_status = TaskStatus.not_started
    task.save!
    task.reload

    clear_submission(task)

    # Now... lets upload a submission with no files
    task.accept_submission user, [], self, nil, 'ready_for_feedback', nil
    assert_equal :ready_for_feedback, task.status

    task.task_status = TaskStatus.not_started
    task.save!

    # Now... lets upload a submission with too many files
    begin
      task.accept_submission user,
        [
          {
            id: 'file0',
            name: 'Document 1',
            type: 'document',
            filename: 'file0.pdf',
            "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
          }
        ], self, nil, 'ready_for_feedback', nil
      assert false, 'Should have raised an error with too many files submitted'
    rescue StandardError => e
      assert_equal :not_started, task.status
    end
  end

  def test_cannot_upload_with_existing_upload_in_process
    project = FactoryBot.create(:project)
    unit = project.unit
    user = project.student
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first

    task_definition.upload_requirements = [
      {
        "key" => 'file0',
        "name" => 'Document 1',
        "type" => 'document'
      }
    ]

    # Saving task def
    task_definition.save!

    # Now... lets upload a submission
    task = project.task_for_task_definition(task_definition)

    # Create a submission
    task.accept_submission user, [
      {
        id: 'file0',
        name: 'Document 1',
        type: 'document',
        filename: 'file0.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      }
    ], self, nil, 'ready_for_feedback', nil, accepted_tii_eula: true

    assert_equal :ready_for_feedback, task.status

    # Now... try uploading again
    begin
      task.accept_submission user,
        [
          {
            id: 'file0',
            name: 'Document 1',
            type: 'document',
            filename: 'file0.pdf',
            "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
          }
        ], self, nil, 'ready_for_feedback', nil
      assert false, 'Should have raised an error with existing upload in process'
    rescue StandardError => e
      assert_includes e.message, 'A submission is already being processed. Please wait for the current submission process to complete.'
      assert_equal :ready_for_feedback, task.status
    end

    FileHelper.move_files(FileHelper.student_work_dir(:new, task, false), FileHelper.student_work_dir(:in_process, task, false), false)

    begin
      task.accept_submission user,
        [
          {
            id: 'file0',
            name: 'Document 1',
            type: 'document',
            filename: 'file0.pdf',
            "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
          }
        ], self, nil, 'ready_for_feedback', nil
      assert false, 'Should have raised an error with existing upload in process'
    rescue StandardError => e
      assert_includes e.message, 'A submission is already being processed. Please wait for the current submission process to complete.'
      assert_equal :ready_for_feedback, task.status
    end

    FileUtils.rm_rf(FileHelper.student_work_dir(:in_process, task, false))

    assert_not task.processing_pdf?

    # Create a submission
    task.accept_submission user, [
      {
        id: 'file0',
        name: 'Document 1',
        type: 'document',
        filename: 'file0.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      }
    ], self, nil, 'ready_for_feedback', nil, accepted_tii_eula: true

    assert_equal :ready_for_feedback, task.status
  ensure
    unit.destroy
  end

  def test_check_files_on_task_move
    project = FactoryBot.create(:project)
    unit = project.unit
    user = project.student
    convenor = unit.main_convenor_user
    task_definition = unit.task_definitions.first

    task_definition.upload_requirements = [
      {
        "key" => 'file0',
        "name" => 'Document 1',
        "type" => 'document'
      }
    ]

    # Saving task def
    task_definition.save!

    # Now... lets upload a submission
    task = project.task_for_task_definition(task_definition)

    # Create a submission
    task.accept_submission user, [
      {
        id: 'file0',
        name: 'Document 1',
        type: 'document',
        filename: 'file0.pdf',
        "tempfile" => File.new(test_file_path('submissions/1.2P.pdf'))
      }
    ], self, nil, 'ready_for_feedback', nil, accepted_tii_eula: true

    # Test that we can move to in process
    assert task.move_files_to_in_process
    assert_not File.exist? FileHelper.student_work_dir(:new, task, false)
    assert File.exist? FileHelper.student_work_dir(:in_process, task, false)

    # Test that we can move back to new
    FileHelper.move_files(FileHelper.student_work_dir(:in_process, task, false), FileHelper.student_work_dir(:new, task, false), false)
    assert File.exist? FileHelper.student_work_dir(:new, task, false)
    assert_not File.exist? FileHelper.student_work_dir(:in_process, task, false)

    # Delete a file and try to compress
    FileUtils.rm("#{FileHelper.student_work_dir(:new, task)}/000-document.pdf")

    assert_not task.compress_new_to_done

    FileHelper.student_work_dir(:new, task, true)
    assert_not task.move_files_to_in_process
  ensure
    unit.destroy
  end
end
