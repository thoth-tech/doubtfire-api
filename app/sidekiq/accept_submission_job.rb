class AcceptSubmissionJob
  include Sidekiq::Job
  include LogHelper

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(args) { [args.first] },
                  on_conflict: :reject,
                  queue: :submissions,
                  retry: false

  def perform(task_id, user_id, accepted_tii_eula, test_submission, *processing_options)
    processing_mode = processing_options.first.to_s
    queued_attempt = processing_options[1]
    restore_archive = %w[retry_archive regenerate_only].include?(processing_mode) || processing_options.first == true
    regeneration_only = processing_mode == 'regenerate_only'
    begin
      # Ensure cwd is valid...
      FileUtils.cd(Rails.root)
    rescue StandardError => e
      logger.error e
    end

    begin
      task = Task.find(task_id).submission_processing_task
      user = User.find(user_id)
    rescue StandardError => e
      logger.error e
      return
    end

    begin
      logger.info "Accepting submission for task #{task.id} by user #{user.id}"
      # Retries and regenerations carry the attempt they were queued for. Once a
      # newer upload has been accepted (possible after the attempt timed out)
      # this job is stale and must not restore the old archive over it. The
      # check, the state change and the restore all happen under the lock the
      # enqueuing request held: a fast worker waits for that request to commit,
      # and no upload can be accepted between the check and the restore.
      stale_attempt = nil
      task.submission_processing_lock_target.with_lock do
        task.reload
        if queued_attempt.present? && task.submission_processing_attempts != queued_attempt.to_i
          stale_attempt = task.submission_processing_attempts
        else
          task.mark_submission_processing!('processing')
          task.prepare_submission_regeneration! if restore_archive
        end
      end

      unless stale_attempt.nil?
        logger.info "Skipping stale submission processing for task #{task.id}: " \
                    "queued for attempt #{queued_attempt}, now at #{stale_attempt}"
        return
      end

      # Convert submission to PDF
      converted = task.convert_submission_to_pdf(log_to_stdout: true)
      raise 'Submission files could not be prepared for conversion.' unless converted
      task.mark_submission_processing!('ready')
    rescue StandardError => e
      task.mark_submission_processing!('failed', error_code: 'conversion_failed')
      logger.error e

      # Send email to student if task pdf failed
      if task.project.student.receive_task_notifications
        begin
          PortfolioEvidenceMailer.task_pdf_failed(task.project, [task]).deliver
        rescue StandardError => e
          logger.error "Failed to send task pdf failed email for project #{task.project.id}!\n#{e.message}"
        end
      end

      begin
        # Notify system admin
        if defined?(Sentry)
          Sentry.capture_exception(
            e,
            extra: {
              task_id: task.id,
              task_definition_abbreviation: task.task_definition.abbreviation,
              latex_log_message: e.respond_to?(:log_message) ? e.log_message.to_s.last(5000) : nil
            }
          )
        end
        mail = ErrorLogMailer.error_message('Accept Submission', "Failed to convert submission to PDF for task #{task.log_details}", e)
        mail.deliver if mail.present?
      rescue StandardError => e
        logger.error "Failed to send error log to admin"
      end

      return
    end

    # Rebuilding a previously ready PDF must not create a duplicate Turnitin
    # submission, moderation decision, or submission-history entry.
    return if regeneration_only

    # Mark this task for moderation
    tutor_user = task.project.tutor_for(task.task_definition)
    if tutor_user && !test_submission
      tutor = task.unit.unit_role_for(tutor_user)
      if tutor&.should_moderate_task?(task)
        logger.info "Marking task #{task.id} for moderation (project #{task.project.id})"
        task.mark_as_moderated
      end
    end

    # When converted, we can now send documents to turn it in for checking
    if TurnItIn.enabled? && !test_submission
      task.send_documents_to_tii(user, accepted_tii_eula: accepted_tii_eula)
    end

    if SubmissionHistory.enabled_requirements(task).any?
      submission_timestamp = Time.now.utc.to_i
      SubmissionHistory.mark_pending(task)
      CreateSubmissionHistoryJob.perform_async(task.id, submission_timestamp, test_submission)
    elsif task.overseer_enabled? || test_submission
      logger.error "Overseer assessment was not performed because task definition #{task.task_definition.id} has no submission history files configured"
    end
  rescue StandardError => e # to raise error message to avoid unnecessary retry
    logger.error e
    if defined?(Sentry)
      Sentry.capture_exception(
        e,
        extra: {
          task_id: task&.id,
          task_definition_abbreviation: task&.task_definition&.abbreviation
        }
      )
    end
    task&.clear_in_process
    if task && !task.submission_pdf_ready?
      task.mark_submission_processing!('failed', error_code: 'processing_failed')
    end
  end
end
