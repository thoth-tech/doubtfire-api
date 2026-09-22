# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'zip'

class SubmissionHistoryAccessTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def setup
    @unit = FactoryBot.create(
      :unit,
      task_count: 1,
      student_count: 3,
      staff_count: 1
    )

    @task_definition = @unit.task_definitions.first
    @owning_project = @unit.active_projects.first
    @other_project = @unit.active_projects.second
    @convenor = @unit.main_convenor_user

    @owning_task = @owning_project.task_for_task_definition(@task_definition)
    @other_task = @other_project.task_for_task_definition(@task_definition)

    @older_history = FactoryBot.create(
      :submission_history,
      task: @owning_task,
      submission_timestamp: (Time.current.to_i - 120).to_s
    )

    @history = FactoryBot.create(
      :submission_history,
      task: @owning_task,
      submission_timestamp: (Time.current.to_i - 60).to_s
    )

    create_archive_for(@history)

    @other_unit = FactoryBot.create(
      :unit,
      task_count: 1,
      student_count: 1,
      staff_count: 1
    )

    @other_unit_task_definition = @other_unit.task_definitions.first
  end

  def teardown
    SubmissionHistory.clear_pending(@owning_task) if @owning_task
    FileUtils.rm_f(@history.archive_file_name) if @history

    @other_unit&.destroy
    @unit&.destroy
  end

  test 'student receives only safe metadata for own history' do
    add_auth_header_for(user: @owning_project.student)

    get metadata_endpoint

    assert_equal 200, last_response.status

    histories = last_response_body
    assert_equal 2, histories.length

    newest = histories.first

    assert_equal @history.id, newest['id']
    assert_equal 1, newest['version_order']
    assert_equal @history.submission_timestamp, newest['submission_timestamp']
    assert_equal 'available', newest['status']

    assert_equal(
      %w[current id status submission_timestamp version_order],
      newest.keys.sort
    )

    older = histories.second
    assert_equal @older_history.id, older['id']
    assert_equal 2, older['version_order']
    assert_equal 'unavailable', older['status']
  end

  test 'unauthorised history requests do not create tasks on another project' do
    @owning_task.destroy!
    add_auth_header_for(user: @other_project.student)

    assert_no_difference('Task.count') do
      get metadata_endpoint
      assert_safe_not_found
      get files_endpoint
      assert_safe_not_found
    end
  end

  test 'own history requests for a missing task are read only' do
    @owning_task.destroy!
    add_auth_header_for(user: @owning_project.student)

    assert_no_difference('Task.count') do
      get metadata_endpoint
      assert_safe_not_found
      get files_endpoint
      assert_safe_not_found
    end
  end

  test 'staff history requests for a missing task are read only' do
    @owning_task.destroy!
    add_auth_header_for(user: @convenor)

    assert_no_difference('Task.count') do
      get metadata_endpoint
      assert_safe_not_found
      get files_endpoint
      assert_safe_not_found
    end
  end

  test 'student can download own retained submission history' do
    add_auth_header_for(user: @owning_project.student)

    get files_endpoint

    assert_equal 200, last_response.status
    assert_match(%r{application/octet-stream}, last_response.headers['Content-Type'])
    assert_match(@owning_project.student.username, last_response.headers['Content-Disposition'])
    assert_match(@task_definition.abbreviation, last_response.headers['Content-Disposition'])

    Zip::File.open_buffer(StringIO.new(last_response.body)) do |archive|
      assert archive.find_entry("#{@owning_task.id}/000-code.rb")
    end
  end

  test 'staff metadata keeps the existing richer contract' do
    add_auth_header_for(user: @convenor)

    get metadata_endpoint

    assert_equal 200, last_response.status

    history = last_response_body.first

    assert history.key?('id')
    assert history.key?('task_id')
    assert history.key?('submission_timestamp')
    assert history.key?('created_at')
    assert history.key?('has_submission_files')
    assert history.key?('overseer_assessment_id')
    assert_not history.key?('version_order')
  end

  test 'staff can still download retained submission history' do
    add_auth_header_for(user: @convenor)

    get files_endpoint

    assert_equal 200, last_response.status
    assert_match(%r{application/octet-stream}, last_response.headers['Content-Type'])
  end

  test 'student cannot read another students history metadata' do
    add_auth_header_for(user: @other_project.student)

    get metadata_endpoint(project: @owning_project)

    assert_safe_not_found
  end

  test 'student cannot download another students history archive' do
    add_auth_header_for(user: @other_project.student)

    get files_endpoint(project: @owning_project)

    assert_safe_not_found
  end

  test 'invalid project id returns the same safe response' do
    add_auth_header_for(user: @owning_project.student)

    invalid_project_id = Project.maximum(:id).to_i + 100_000

    get metadata_endpoint(project_id: invalid_project_id)

    assert_safe_not_found
  end

  test 'task definition from another unit returns the same safe response' do
    add_auth_header_for(user: @owning_project.student)

    get metadata_endpoint(task_definition: @other_unit_task_definition)

    assert_safe_not_found
  end

  test 'substituted history id cannot escape the authorised task' do
    foreign_history = FactoryBot.create(
      :submission_history,
      task: @other_task,
      submission_timestamp: (Time.current.to_i - 300).to_s
    )

    add_auth_header_for(user: @owning_project.student)

    get files_endpoint(history: foreign_history)

    assert_safe_not_found
  end

  test 'invalid history id returns the same safe response' do
    add_auth_header_for(user: @owning_project.student)

    invalid_history_id = SubmissionHistory.maximum(:id).to_i + 100_000

    get files_endpoint(history_id: invalid_history_id)

    assert_safe_not_found
  end

  test 'missing retained archive is reported as unavailable' do
    add_auth_header_for(user: @owning_project.student)

    get files_endpoint(history: @older_history)

    assert_equal 404, last_response.status
    assert_equal(
      'Submission history files are not available',
      last_response_body['error']
    )
  end

  test 'pending archive creation is exposed as processing without a fake history id' do
    SubmissionHistory.mark_pending(@owning_task)

    add_auth_header_for(user: @owning_project.student)

    get metadata_endpoint

    assert_equal 202, last_response.status
    assert_kind_of Array, last_response_body

    ids = last_response_body.map { |history| history['id'] }
    assert_includes ids, @history.id
    assert_not_includes ids, nil
  ensure
    SubmissionHistory.clear_pending(@owning_task)
  end

  test 'joining the current group later does not grant access to older history' do
    group_set = FactoryBot.create(:group_set, unit: @unit)
    group = FactoryBot.create(
      :group,
      group_set: group_set,
      tutorial: @unit.tutorials.first
    )

    group.add_member(@owning_project, notify: false)

    group_submission = GroupSubmission.create!(
      group: group,
      task_definition: @task_definition,
      submitted_by_project: @owning_project
    )

    @owning_task.update!(group_submission: group_submission)

    historical_group_history = FactoryBot.create(
      :submission_history,
      task: @owning_task,
      submission_timestamp: (Time.current.to_i - 600).to_s
    )

    group.add_member(@other_project, notify: false)

    assert_includes group.reload.projects, @other_project

    add_auth_header_for(user: @other_project.student)

    get files_endpoint(
      project: @owning_project,
      history: historical_group_history
    )

    assert_safe_not_found
  end

  test 'current version is distinguished from older retained and processing versions' do
    @owning_task.update_columns(submission_processing_started_at: Time.at(@history.submission_timestamp.to_i - 1))
    add_auth_header_for(user: @owning_project.student)
    get metadata_endpoint
    assert_equal true, last_response_body.first['current']
    assert_equal false, last_response_body.second['current']
    SubmissionHistory.mark_pending(@owning_task)
    get metadata_endpoint
    assert_equal 202, last_response.status
    assert last_response_body.none? { |version| version['current'] }
  end

  test 'corrupt retained archive is unavailable and cannot be downloaded' do
    File.binwrite(@history.archive_file_name, 'not a zip archive')
    add_auth_header_for(user: @owning_project.student)
    get metadata_endpoint
    assert_equal 'unavailable', last_response_body.first['status']
    get files_endpoint
    assert_equal 404, last_response.status
  end

  test 'removed records and no history return an empty list without a fake version' do
    @owning_task.submission_histories.destroy_all
    add_auth_header_for(user: @owning_project.student)
    get metadata_endpoint
    assert_equal 200, last_response.status
    assert_equal [], last_response_body
  end

  test 'leaving a group preserves access only to archives retained on the students own task' do
    group_set = FactoryBot.create(:group_set, unit: @unit)
    group = FactoryBot.create(:group, group_set: group_set, tutorial: @unit.tutorials.first)
    group.add_member(@owning_project, notify: false)
    group.add_member(@other_project, notify: false)
    group_submission = GroupSubmission.create!(group: group, task_definition: @task_definition,
                                                submitted_by_project: @owning_project)
    @owning_task.update!(group_submission: group_submission)
    group.remove_member(@owning_project, notify: false)
    add_auth_header_for(user: @owning_project.student)
    get files_endpoint
    assert_equal 200, last_response.status
    get metadata_endpoint(project: @other_project)
    assert_safe_not_found
  end

  test 'numeric timestamps order legacy and modern versions deterministically' do
    legacy = FactoryBot.create(:submission_history, task: @owning_task, submission_timestamp: '999999999')
    add_auth_header_for(user: @owning_project.student)
    get metadata_endpoint
    assert_equal [@history.id, @older_history.id, legacy.id], last_response_body.map { |version| version['id'] }
  end

  private

  def metadata_endpoint(
    project: @owning_project,
    project_id: nil,
    task_definition: @task_definition
  )
    id = project_id || project.id

    "/api/projects/#{id}/task_def_id/#{task_definition.id}/submission_histories"
  end

  def files_endpoint(
    project: @owning_project,
    task_definition: @task_definition,
    history: @history,
    history_id: nil
  )
    id = history_id || history.id

    "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/submission_histories/#{id}/files"
  end

  def assert_safe_not_found
    assert_equal 404, last_response.status
    assert_equal 'Submission history is not available', last_response_body['error']
  end

  def create_archive_for(history)
    FileUtils.mkdir_p(history.output_path)
    FileUtils.rm_f(history.archive_file_name)

    Zip::File.open(history.archive_file_name, create: true) do |archive|
      entry_name =
        "#{history.submission_timestamp}/#{history.task.id}/000-code.rb"

      archive.get_output_stream(entry_name) do |file|
        file.write('puts "retained submission"')
      end
    end
  end
end
