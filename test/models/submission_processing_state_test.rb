require 'test_helper'

class SubmissionProcessingStateTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    @task = FactoryBot.create(:task)
  end

  def test_active_queue_becomes_finite_timed_out_state
    @task.update!(
      submission_processing_state: 'queued',
      submission_processing_started_at: 11.minutes.ago
    )

    @task.stub(:submission_pdf_ready?, false) do
      @task.stub(:submission_files_ready?, true) do
        snapshot = @task.submission_processing_snapshot

        assert_equal 'timed_out', snapshot[:processing_state]
        assert_not snapshot[:processing_pdf]
        assert snapshot[:retryable]
        assert snapshot[:submission_files_ready]
      end
    end
  end

  def test_ready_snapshot_reports_each_real_artifact_independently
    @task.update!(submission_processing_state: 'ready')

    @task.stub(:submission_pdf_ready?, true) do
      @task.stub(:submission_files_ready?, true) do
        snapshot = @task.submission_processing_snapshot

        assert_equal 'ready', snapshot[:processing_state]
        assert snapshot[:has_pdf]
        assert snapshot[:pdf_ready]
        assert snapshot[:submission_files_ready]
        assert_not snapshot[:retryable]
      end
    end
  end

  def test_previous_attempt_pdf_is_not_ready_for_a_new_attempt
    Dir.mktmpdir do |directory|
      pdf_path = File.join(directory, 'submission.pdf')
      File.write(pdf_path, 'old submission')
      old_time = 5.minutes.ago
      File.utime(old_time.to_time, old_time.to_time, pdf_path)
      @task.update!(submission_processing_started_at: Time.current)

      @task.stub(:final_pdf_path, pdf_path) do
        assert_not @task.submission_pdf_ready?
      end
    end
  end

  def test_current_attempt_pdf_completes_a_stale_rolling_deploy_state
    @task.update!(
      submission_processing_state: 'queued',
      submission_processing_started_at: 1.minute.ago
    )

    @task.stub(:submission_pdf_ready?, true) do
      @task.stub(:processing_pdf?, false) do
        assert_equal 'ready', @task.effective_submission_processing_state
      end
    end
  end

  def test_marking_a_new_attempt_clears_failure_and_increments_attempts
    @task.update!(
      submission_processing_state: 'failed',
      submission_processing_error_code: 'conversion_failed',
      submission_processing_attempts: 1
    )

    @task.mark_submission_processing!('queued', now: Time.zone.parse('2026-08-31 10:00:00'))
    @task.reload

    assert_equal 'queued', @task.submission_processing_state
    assert_equal 2, @task.submission_processing_attempts
    assert_nil @task.submission_processing_error_code
    assert_nil @task.submission_processing_finished_at
    assert_equal Time.zone.parse('2026-08-31 10:00:00'), @task.submission_processing_started_at
  end

  def test_retry_requeues_only_the_preserved_submission_archive
    user = @task.project.student
    queued = false

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, false) do
        @task.stub(:folder_exists_in_process?, false) do
          @task.stub(:submission_files_ready?, true) do
            AcceptSubmissionJob.stub(:perform_async, lambda { |task_id, user_id, _tii, _test, processing_mode, _attempt|
              queued = task_id == @task.id && user_id == user.id && processing_mode == 'retry_archive'
              'job-id'
            }) do
              @task.retry_submission_processing!(user)
            end
          end
        end
      end
    end

    assert queued
    assert_equal 'queued', @task.reload.submission_processing_state
  end

  def test_timed_out_unprocessed_upload_can_requeue_its_staged_files
    user = @task.project.student
    queued_without_regeneration = false

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, true) do
        @task.stub(:folder_exists_in_process?, false) do
          AcceptSubmissionJob.stub(:perform_async, lambda { |_task_id, _user_id, _tii, _test, processing_mode, _attempt|
            queued_without_regeneration = processing_mode == 'process'
            'job-id'
          }) do
            @task.retry_submission_processing!(user)
          end
        end
      end
    end

    assert queued_without_regeneration
  end

  def test_queue_conflict_rolls_back_retry_state
    user = @task.project.student
    @task.update!(
      submission_processing_state: 'failed',
      submission_processing_error_code: 'conversion_failed',
      submission_processing_attempts: 2
    )

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, true) do
        @task.stub(:folder_exists_in_process?, false) do
          AcceptSubmissionJob.stub(:perform_async, nil) do
            assert_raises(ArgumentError) { @task.retry_submission_processing!(user) }
          end
        end
      end
    end

    @task.reload
    assert_equal 'failed', @task.submission_processing_state
    assert_equal 2, @task.submission_processing_attempts
    assert_equal 'conversion_failed', @task.submission_processing_error_code
  end

  def test_failed_archive_extraction_preserves_existing_work_directories
    Dir.mktmpdir do |directory|
      new_path = File.join(directory, 'new', @task.id.to_s)
      in_process_path = File.join(directory, 'in_process', @task.id.to_s)
      zip_path = File.join(directory, 'submission.zip')
      FileUtils.mkdir_p(new_path)
      FileUtils.mkdir_p(in_process_path)
      File.write(File.join(new_path, 'new-marker'), 'new')
      File.write(File.join(in_process_path, 'processing-marker'), 'processing')
      File.write(zip_path, 'not a zip archive')

      work_dir = lambda do |type, _create = true|
        type == :new ? "#{new_path}/" : "#{in_process_path}/"
      end

      @task.stub(:zip_file_path_for_done_task, zip_path) do
        @task.stub(:student_work_dir, work_dir) do
          assert_raises(Zip::Error) { @task.prepare_submission_regeneration! }
        end
      end

      assert File.file?(File.join(new_path, 'new-marker'))
      assert File.file?(File.join(in_process_path, 'processing-marker'))
    end
  end

  def test_group_member_uses_the_submitter_as_processing_identity
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
    task_definition = FactoryBot.create(
      :task_definition,
      unit: unit,
      group_set: unit.group_sets.first
    )
    group = unit.groups.first
    submitter_project, member_project = group.projects.first(2)
    submitter = submitter_project.task_for_task_definition(task_definition)
    member = member_project.task_for_task_definition(task_definition)
    group_submission = GroupSubmission.create!(
      group: group,
      task_definition: task_definition,
      submitted_by_project: submitter_project
    )
    submitter.update!(group_submission: group_submission)
    member.update!(group_submission: group_submission)

    assert_equal submitter.id, member.submission_processing_task.id
    assert_equal group.id, member.submission_processing_lock_target.id

    member.mark_submission_processing!('queued', now: Time.zone.parse('2026-08-31 12:00:00'))

    [submitter, member].each do |task|
      task.reload
      assert_equal 'queued', task.submission_processing_state
      assert_equal 1, task.submission_processing_attempts
      assert_equal Time.zone.parse('2026-08-31 12:00:00'), task.submission_processing_started_at
    end
  end

  def test_submission_job_uses_the_dedicated_queue
    assert_equal :submissions, AcceptSubmissionJob.get_sidekiq_options['queue']
  end

  def test_group_regeneration_restores_the_archive_through_the_submitter
    fixture = group_submission_fixture
    submitter = fixture.fetch(:submitter)
    zip_path = submitter.zip_file_path_for_done_task
    new_path = submitter.student_work_dir(:new, false)
    FileUtils.mkdir_p(File.dirname(zip_path))
    Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
      zip.get_output_stream("#{submitter.id}/000-document.pdf") { |stream| stream.write('restored') }
    end

    # The member resolves the submitter through a freshly loaded instance.
    assert fixture.fetch(:member).prepare_submission_regeneration!
    assert_equal 'restored', File.read(File.join(new_path, '000-document.pdf'))
  ensure
    FileUtils.rm_f(zip_path) if zip_path
    FileUtils.rm_rf(new_path) if new_path
  end

  def test_a_new_upload_is_refused_while_a_regeneration_is_queued
    user = @task.project.student
    @task.stub(:submission_files_ready?, true) do
      AcceptSubmissionJob.stub(:perform_async, 'job-id') do
        @task.regenerate_submission!(user)
      end
    end
    ui = Object.new
    def ui.error!(body, status)
      raise ArgumentError, "#{status} #{body['error']}"
    end

    # The regeneration has staged no files yet, so only its recorded mode
    # shows that an upload now would be replaced by the old archive.
    assert_not @task.processing_pdf?
    error = assert_raises(ArgumentError) do
      @task.accept_submission(user, nil, ui, nil, 'ready_for_feedback', nil)
    end

    assert_match(/already being processed/, error.message)
    assert_equal 'regenerate_only', @task.reload.submission_processing_mode
  end

  def test_retry_replays_the_options_the_upload_was_accepted_with
    user = @task.project.student
    @task.mark_submission_processing!('queued', user_id: user.id, test_submission: true, accepted_tii_eula: true)
    @task.mark_submission_processing!('failed', error_code: 'conversion_failed')
    replayed = nil

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, false) do
        @task.stub(:folder_exists_in_process?, false) do
          @task.stub(:submission_files_ready?, true) do
            AcceptSubmissionJob.stub(:perform_async, lambda { |_task_id, _user_id, tii, test, processing_mode, _attempt|
              replayed = [tii, test, processing_mode]
              'job-id'
            }) do
              @task.retry_submission_processing!(user)
            end
          end
        end
      end
    end

    assert_equal [true, true, 'retry_archive'], replayed
    assert @task.reload.submission_processing_test_submission, 'a retry keeps the recorded options'
  end

  def test_a_retry_by_someone_else_replays_the_uploaders_attempt
    student = @task.project.student
    tutor = FactoryBot.create(:user)
    @task.mark_submission_processing!('queued', user_id: student.id, test_submission: false, accepted_tii_eula: true)
    @task.mark_submission_processing!('failed', error_code: 'conversion_failed')
    replayed = nil

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, false) do
        @task.stub(:folder_exists_in_process?, false) do
          @task.stub(:submission_files_ready?, true) do
            AcceptSubmissionJob.stub(:perform_async, lambda { |_task_id, user_id, tii, _test, _processing_mode, attempt|
              replayed = [user_id, tii, attempt]
              'job-id'
            }) do
              @task.retry_submission_processing!(tutor)
            end
          end
        end
      end
    end

    # The student's consent travels with the student, not with the tutor.
    assert_equal [student.id, true, 2], replayed
  end

  def test_consent_is_not_replayed_when_the_uploader_no_longer_exists
    caller = FactoryBot.create(:user)
    @task.mark_submission_processing!('queued', user_id: 0, accepted_tii_eula: true)
    @task.mark_submission_processing!('failed', error_code: 'conversion_failed')
    replayed = nil

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, false) do
        @task.stub(:folder_exists_in_process?, false) do
          @task.stub(:submission_files_ready?, true) do
            AcceptSubmissionJob.stub(:perform_async, lambda { |_task_id, user_id, tii, _test, _processing_mode, _attempt|
              replayed = [user_id, tii]
              'job-id'
            }) do
              @task.retry_submission_processing!(caller)
            end
          end
        end
      end
    end

    assert_equal [caller.id, false], replayed
  end

  def test_files_staged_after_ready_are_reported_as_a_newer_attempt
    Dir.mktmpdir do |directory|
      pdf_path = File.join(directory, 'submission.pdf')
      File.write(pdf_path, 'previous attempt')
      # A previous-release API staged a new upload after this attempt was ready.
      @task.update!(submission_processing_state: 'ready', submission_processing_started_at: 1.hour.ago)

      @task.stub(:final_pdf_path, pdf_path) do
        @task.stub(:processing_pdf?, true) do
          @task.stub(:folder_exists_in_process?, false) do
            @task.stub(:submission_processing_file_timestamp, 1.minute.ago) do
              snapshot = @task.submission_processing_snapshot

              assert_equal 'queued', snapshot[:processing_state]
              assert snapshot[:processing_pdf]
              assert_not snapshot[:has_pdf]
              assert_not snapshot[:pdf_ready]
            end
          end
        end
      end
    end
  end

  def test_a_failed_backup_move_leaves_the_staged_upload_in_place
    Dir.mktmpdir do |directory|
      new_path = File.join(directory, 'new', @task.id.to_s)
      in_process_path = File.join(directory, 'in_process', @task.id.to_s)
      FileUtils.mkdir_p(new_path)
      File.write(File.join(new_path, 'staged-marker'), 'staged')
      zip_path = File.join(directory, 'submission.zip')
      Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
        zip.get_output_stream("#{@task.id}/000-document.pdf") { |stream| stream.write('archived') }
      end
      work_dir = lambda do |type, _create = true|
        type == :new ? "#{new_path}/" : "#{in_process_path}/"
      end
      original_mv = FileUtils.method(:mv)
      failing_backup_mv = lambda do |source, destination, **options|
        raise Errno::EACCES, 'simulated backup failure' if source.to_s == new_path

        original_mv.call(source, destination, **options)
      end

      @task.stub(:zip_file_path_for_done_task, zip_path) do
        @task.stub(:student_work_dir, work_dir) do
          FileUtils.stub(:mv, failing_backup_mv) do
            assert_raises(Errno::EACCES) { @task.prepare_submission_regeneration! }
          end
        end
      end

      assert_equal 'staged', File.read(File.join(new_path, 'staged-marker'))
    end
  end

  def test_a_failed_regeneration_is_retried_as_a_regeneration
    user = @task.project.student
    @task.mark_submission_processing!('queued', processing_mode: 'regenerate_only')
    @task.mark_submission_processing!('failed', error_code: 'conversion_failed')
    replayed_mode = nil

    @task.stub(:submission_processing_retryable?, true) do
      @task.stub(:folder_exists_in_new?, false) do
        @task.stub(:folder_exists_in_process?, false) do
          @task.stub(:submission_files_ready?, true) do
            AcceptSubmissionJob.stub(:perform_async, lambda { |_task_id, _user_id, _tii, _test, processing_mode, _attempt|
              replayed_mode = processing_mode
              'job-id'
            }) do
              @task.retry_submission_processing!(user)
            end
          end
        end
      end
    end

    # Not retry_archive, which would run Turnitin, moderation and history again.
    assert_equal 'regenerate_only', replayed_mode
  end

  def test_a_pdf_written_after_a_failure_makes_the_submission_ready_again
    Dir.mktmpdir do |directory|
      pdf_path = File.join(directory, 'submission.pdf')
      File.write(pdf_path, 'replacement')
      @task.update!(
        submission_processing_state: 'failed',
        submission_processing_started_at: 20.minutes.ago,
        submission_processing_finished_at: 10.minutes.ago
      )

      @task.stub(:final_pdf_path, pdf_path) do
        @task.stub(:processing_pdf?, false) do
          snapshot = @task.submission_processing_snapshot
          assert_equal 'ready', snapshot[:processing_state]
          assert snapshot[:has_pdf]

          # A PDF from before the failure does not count.
          File.utime(15.minutes.ago.to_time, 15.minutes.ago.to_time, pdf_path)
          assert_equal 'failed', @task.effective_submission_processing_state
        end
      end
    end
  end

  def test_an_unsubmitted_group_task_reports_its_state
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
    task = unit.groups.first.projects.first.task_for_task_definition(task_definition)
    task.save! if task.new_record?

    # No group submission yet, so there is no done folder to resolve.
    assert task.group_task?
    assert_nil task.group_submission
    snapshot = task.submission_processing_snapshot

    assert_equal 'not_submitted', snapshot[:processing_state]
    assert_not snapshot[:submission_files_ready]
  end

  def test_an_uncompressed_done_folder_can_still_be_regenerated
    Dir.mktmpdir do |directory|
      new_path = File.join(directory, 'new', @task.id.to_s)
      in_process_path = File.join(directory, 'in_process', @task.id.to_s)
      done_path = File.join(directory, 'done', @task.id.to_s)
      FileUtils.mkdir_p(done_path)
      File.write(File.join(done_path, '000-document.pdf'), 'kept')
      work_dir = lambda do |type, _create = true|
        { new: "#{new_path}/", in_process: "#{in_process_path}/", done: "#{done_path}/" }.fetch(type)
      end

      @task.stub(:zip_file_path_for_done_task, File.join(directory, 'missing.zip')) do
        @task.stub(:student_work_dir, work_dir) do
          assert @task.submission_files_ready?
          assert @task.prepare_submission_regeneration!
        end
      end

      assert_equal 'kept', File.read(File.join(new_path, '000-document.pdf'))
    end
  end

  private

  def group_submission_fixture
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
    task_definition = FactoryBot.create(
      :task_definition,
      unit: unit,
      group_set: unit.group_sets.first
    )
    group = unit.groups.first
    submitter_project, member_project = group.projects.first(2)
    submitter = submitter_project.task_for_task_definition(task_definition)
    member = member_project.task_for_task_definition(task_definition)
    group_submission = GroupSubmission.create!(
      group: group,
      task_definition: task_definition,
      submitted_by_project: submitter_project
    )
    submitter.update!(group_submission: group_submission)
    member.update!(group_submission: group_submission)

    { submitter: submitter, member: member }
  end
end
