require 'test_helper'

class AcceptSubmissionJobTest < ActiveSupport::TestCase
  def test_pdf_regeneration_stops_before_submission_side_effects
    task = FactoryBot.create(:task)
    user = task.project.student
    states = []
    restored = false

    task.stub(:mark_submission_processing!, ->(state, **_options) { states << state }) do
      task.stub(:prepare_submission_regeneration!, -> { restored = true }) do
        task.stub(:convert_submission_to_pdf, true) do
          task.stub(:project, -> { raise 'submission side effects must not run' }) do
            Task.stub(:find, task) do
              User.stub(:find, user) do
                AcceptSubmissionJob.new.perform(task.id, user.id, false, false, 'regenerate_only')
              end
            end
          end
        end
      end
    end

    assert restored
    assert_equal %w[processing ready], states
  end

  def test_a_stale_restore_leaves_a_newer_upload_alone
    task = FactoryBot.create(:task)
    user = task.project.student
    # Queued as attempt 1, but a newer upload has since been accepted as attempt 2.
    task.update!(submission_processing_state: 'failed', submission_processing_attempts: 2)
    touched = []

    task.stub(:mark_submission_processing!, ->(state, **_options) { touched << state }) do
      task.stub(:prepare_submission_regeneration!, -> { touched << :restore }) do
        task.stub(:convert_submission_to_pdf, ->(**_options) { touched << :convert }) do
          Task.stub(:find, task) do
            User.stub(:find, user) do
              AcceptSubmissionJob.new.perform(task.id, user.id, false, false, 'retry_archive', 1)
            end
          end
        end
      end
    end

    assert_empty touched
  end

  def test_the_archive_is_restored_while_the_submission_lock_is_held
    task = FactoryBot.create(:task)
    user = task.project.student
    task.update!(submission_processing_state: 'queued', submission_processing_attempts: 1)
    outer_transactions = Task.connection.open_transactions
    restored_under_lock = nil

    # Uploads take the same lock, so none can land between the check and here.
    task.stub(:prepare_submission_regeneration!, -> { restored_under_lock = Task.connection.open_transactions > outer_transactions }) do
      task.stub(:convert_submission_to_pdf, ->(**_options) { true }) do
        Task.stub(:find, task) do
          User.stub(:find, user) do
            AcceptSubmissionJob.new.perform(task.id, user.id, false, false, 'regenerate_only', 1)
          end
        end
      end
    end

    assert restored_under_lock
    assert_equal 'ready', task.reload.submission_processing_state
  end

  def test_the_attempt_check_reads_the_stored_row_not_the_loaded_object
    task = FactoryBot.create(:task)
    user = task.project.student
    task.update!(submission_processing_state: 'failed', submission_processing_attempts: 1)
    # The retry that queued this job recorded attempt 2 after the worker
    # loaded its copy of the task.
    Task.where(id: task.id).update_all(submission_processing_state: 'queued', submission_processing_attempts: 2) # rubocop:disable Rails/SkipsModelValidations
    touched = []

    task.stub(:mark_submission_processing!, ->(state, **_options) { touched << state }) do
      task.stub(:prepare_submission_regeneration!, -> { touched << :restore }) do
        task.stub(:convert_submission_to_pdf, ->(**_options) { true }) do
          task.stub(:project, -> { raise 'stop after conversion' }) do
            Task.stub(:find, task) do
              User.stub(:find, user) do
                AcceptSubmissionJob.new.perform(task.id, user.id, false, false, 'regenerate_only', 2)
              end
            end
          end
        end
      end
    end

    assert_equal ['processing', :restore, 'ready'], touched
  end
end
