# frozen_string_literal: true

require 'test_helper'

# POST /api/projects/:id/task_def_id/:task_definition_id/submission/retry
class SubmissionProcessingApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def retry_endpoint(project, task_definition)
    "/api/projects/#{project.id}/task_def_id/#{task_definition.id}/submission/retry"
  end

  # The retry restores the done archive, so the task needs one on disk.
  def write_done_archive(task, archive_task = task)
    zip_path = task.zip_file_path_for_done_task
    FileUtils.mkdir_p(File.dirname(zip_path))
    Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
      zip.get_output_stream("#{archive_task.id}/000-document.pdf") { |stream| stream.write('archived') }
    end
    zip_path
  end

  def record_enqueued_jobs(jobs, &)
    enqueue = lambda do |*args|
      jobs << args
      'job-id'
    end
    AcceptSubmissionJob.stub(:perform_async, enqueue, &)
  end

  test 'retrying a failed conversion queues the preserved archive and reports the new state' do
    project = FactoryBot.create(:project)
    task_definition = project.unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)
    task.update!(
      submission_date: 1.hour.ago,
      submission_processing_state: 'failed',
      submission_processing_error_code: 'conversion_failed',
      submission_processing_attempts: 1
    )
    zip_path = write_done_archive(task)
    jobs = []

    add_auth_header_for(user: project.student)
    record_enqueued_jobs(jobs) do
      post retry_endpoint(project, task_definition)
    end

    assert_equal 201, last_response.status, last_response.body
    assert_equal 'queued', last_response_body['processing_state']
    assert_equal 2, last_response_body['processing_attempts']
    assert_equal true, last_response_body['processing_pdf']
    # No uploader was recorded for this attempt, so the caller is used.
    assert_equal [[task.id, project.student.id, false, false, 'retry_archive', 2]], jobs
  ensure
    FileUtils.rm_f(zip_path) if zip_path
  end

  test 'a group retry reports the state written through the submitter task' do
    unit = FactoryBot.create(
      :unit,
      group_sets: 1,
      groups: [{ gs: 0, students: 2 }],
      student_count: 2,
      unenrolled_student_count: 0,
      part_enrolled_student_count: 0,
      inactive_student_count: 0,
      task_count: 0
    )
    task_definition = FactoryBot.create(:task_definition, unit: unit, group_set: unit.group_sets.first)
    group = unit.groups.first
    submitter_project, member_project = group.projects.first(2)
    submitter = submitter_project.task_for_task_definition(task_definition)
    member = member_project.task_for_task_definition(task_definition)
    group_submission = GroupSubmission.create!(
      group: group,
      task_definition: task_definition,
      submitted_by_project: submitter_project
    )
    [submitter, member].each do |task|
      task.update!(
        group_submission: group_submission,
        submission_date: 1.hour.ago,
        submission_processing_state: 'failed',
        submission_processing_attempts: 1
      )
    end
    zip_path = write_done_archive(submitter.reload)
    jobs = []

    # The member asks, the submitter's task is the one that is processed.
    add_auth_header_for(user: member_project.student)
    record_enqueued_jobs(jobs) do
      post retry_endpoint(member_project, task_definition)
    end

    assert_equal 201, last_response.status, last_response.body
    assert_equal 'queued', last_response_body['processing_state']
    assert_equal 2, last_response_body['processing_attempts']
    assert_equal submitter.id, jobs.first.first
    # The job must carry the attempt that was just recorded, or it stands down.
    assert_equal 2, jobs.first.last
    assert_equal 'queued', member.reload.submission_processing_state
  ensure
    FileUtils.rm_f(zip_path) if zip_path
  end

  test 'a submission that has not failed cannot be retried' do
    project = FactoryBot.create(:project)
    task_definition = project.unit.task_definitions.first
    task = project.task_for_task_definition(task_definition)
    task.update!(submission_processing_state: 'queued', submission_processing_started_at: Time.current)
    jobs = []

    add_auth_header_for(user: project.student)
    record_enqueued_jobs(jobs) do
      post retry_endpoint(project, task_definition)
    end

    assert_equal 409, last_response.status, last_response.body
    assert_empty jobs
    assert_equal 'queued', task.reload.submission_processing_state
  end
end
