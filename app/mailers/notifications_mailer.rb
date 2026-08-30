class NotificationsMailer < ApplicationMailer
  def add_general
    @doubtfire_host = Doubtfire::Application.config.institution[:host]
    @doubtfire_product_name = Doubtfire::Application.config.institution[:product_name]
    @unsubscribe_url = "#{@doubtfire_host}/edit_profile"
  end

  # Sends a single in-system notification as an email. Called by
  # NotificationEmailJob, which lets delivery failures reach Sidekiq so they can
  # be retried without blocking the request that created the notification.
  def single_notification(notification)
    add_general

    @notification = notification
    @user = notification.user

    # Use the deployment's SMTP-authorised sender, with a development-safe
    # fallback for older installations that have not configured one yet.
    from_address = Doubtfire::Application.config.institution[:email_sender].presence || 'noreply@doubtfire.local'

    email_with_name = %("#{@user.name}" <#{@user.email}>)
    subject = "#{@doubtfire_product_name}: New notification"

    # An event may ship its own pair of templates named after it, for example
    # task_comment_created.html.erb and task_comment_created.text.erb. Events
    # without them fall back to the generic single_notification pair.
    #
    # This is why a new event ticket only ever adds files and never edits this
    # method: eight event tickets can run in parallel without touching each
    # other's work.
    mail(
      to: email_with_name,
      from: from_address,
      subject: subject,
      template_name: event_template_name(notification.event)
    )
  end

  # The event's own template if it exists, otherwise the generic one.
  def event_template_name(event)
    return 'single_notification' if event.blank?
    return 'single_notification' unless lookup_context.exists?(event, [self.class.mailer_name], false)

    event
  end

  def weekly_staff_summary(unit_role, summary_stats)
    return nil if unit_role.nil?

    add_general

    @staff = unit_role.user
    @unit_role = unit_role
    @unit = summary_stats[:unit]

    @received_comments = @unit.comments
                              .where("task_comments.recipient_id = :uid AND task_comments.created_at > :start", uid: @staff.id, start: 7.days.ago)
                              .where(content_type: [:text, :assessment, :audio, :image, :pdf, :discussion, :extension])
                              .count

    @sent_comments = @unit.comments
                          .where("task_comments.user_id = :uid AND task_comments.created_at > :start", uid: @staff.id, start: 7.days.ago)
                          .where(content_type: [:text, :assessment, :audio, :image, :pdf, :discussion, :extension])
                          .count

    @data = {
      sent_comments: @sent_comments, # Sent by tutor
      received_comments: @received_comments, # Received by tutor
      tasks_awaiting_feedback_count: summary_stats[:staff][unit_role.user][:tasks_awaiting_feedback_count], # For the tutor
      weekly_engagements_count: summary_stats[:staff][unit_role.user][:weekly_engagements_count], # Engagements from the student?
      staff_engagements: summary_stats[:staff][unit_role.user][:staff_engagements], # Engagements by the tutor
      oldest_task_days: summary_stats[:staff][unit_role.user][:oldest_task_days],
      weekly_total_tasks_discussed: summary_stats[:staff][unit_role.user][:weekly_total_tasks_discussed] # Total for the tutor for the week for the tutor
    }

    @convenor = @unit.main_convenor_user
    @summary_stats = summary_stats

    email_with_name = %("#{@staff.name}" <#{@staff.email}>)
    convenor_email = %("#{@convenor.name}" <#{@convenor.email}>)
    subject = "#{@unit.name}: Weekly Summary"

    mail(to: email_with_name, from: convenor_email, subject: subject)
  end

  def weekly_student_summary(project, summary_stats, did_revert_to_pass)
    return nil if project.nil?

    add_general

    @student = project.student
    @project = project
    @tutor = project.main_convenor_user
    @summary_stats = summary_stats
    @did_revert_to_pass = did_revert_to_pass

    @engagements = @project.task_engagements.where("task_engagements.engagement_time >= :start AND task_engagements.engagement_time < :end", start: summary_stats[:week_start], end: summary_stats[:week_end])

    @engagements_count = @engagements.count

    @student_engagements = @engagements.select { |e| [TaskStatus.not_started.name, TaskStatus.need_help.name, TaskStatus.working_on_it.name, TaskStatus.ready_for_feedback.name].include? e.engagement }.count

    @staff_engagements = @engagements.select { |e| [TaskStatus.complete.name, TaskStatus.feedback_exceeded.name, TaskStatus.redo.name, TaskStatus.discuss.name, TaskStatus.rediscuss.name, TaskStatus.attention_required.name, TaskStatus.demonstrate.name, TaskStatus.fail.name].include? e.engagement }.count

    @task_states = project.tasks.joins(:task_status).select("count(tasks.id) as number, task_statuses.name as status").group("task_statuses.name")

    @received_comments = project.comments.where("recipient_id = :student_id AND task_comments.created_at > :start", student_id: @student.id, start: Time.zone.now - 7.days).count
    @sent_comments = project.comments.where("user_id = :student_id AND task_comments.created_at > :start", student_id: @student.id, start: Time.zone.now - 7.days).count

    @top_tasks = project.top_tasks
    @overdue_top = @top_tasks.select { |tt| tt[:reason] == :overdue }
    @soon_top = @top_tasks.select { |tt| tt[:reason] == :soon }
    @ahead_top = @top_tasks.select { |tt| tt[:reason] == :ahead }

    email_with_name = %("#{@student.name}" <#{@student.email}>)
    tutor_email = %("#{@tutor.name}" <#{@tutor.email}>)
    subject = "#{project.unit.name}: Weekly Summary"

    mail(to: email_with_name, from: tutor_email, subject: subject)
  end

  def top_task_desc(tt)
    "#{tt[:task_definition].abbreviation} - #{tt[:task_definition].name} #{"- which you need to discuss with your tutor" if tt[:status] == :discuss}"
  end

  def were_was(num)
    if num == 1
      "was"
    else
      "were"
    end
  end

  def are_is(num)
    if num == 1
      "is"
    else
      "are"
    end
  end

  def this_these(num)
    if num == 1
      "this"
    else
      "these"
    end
  end

  helper_method :top_task_desc
  helper_method :were_was
  helper_method :are_is
  helper_method :this_these
end
