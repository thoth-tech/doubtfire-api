class PortfolioEvidenceMailer < ApplicationMailer
  layout "notification_mail"

  def add_general
    @doubtfire_host = Doubtfire::Application.config.institution[:host]
    @doubtfire_product_name = Doubtfire::Application.config.institution[:product_name]
    @unsubscribe_url = "#{@doubtfire_host}/edit_profile"
  end

  def task_pdf_failed(project, tasks)
    return nil if project.nil? || tasks.nil? || tasks.empty?

    add_general
    @student = project.student
    @project = project
    @tasks = tasks.sort_by { |t| t.task_definition.abbreviation }
    @tutor = project.main_convenor_user
    @convenor = project.main_convenor_user

    email_with_name = address_with_name(@student)
    tutor_email = address_with_name(@tutor)
    subject = "#{project.unit.code} #{project.unit.name}: Task submission processing failed"
    mail(
      { to: email_with_name, subject: subject }.merge(
        outbound_sender_headers(development_from: tutor_email, reply_to: tutor_email)
      )
    )
  end

  def task_pdf_ready_message(project, tasks)
    return nil if project.nil? || tasks.nil? || tasks.empty?

    add_general
    @student = project.student
    @project = project
    @tasks = tasks.sort_by { |t| t.task_definition.abbreviation }
    @tutor = project.main_convenor_user
    @convenor = project.main_convenor_user

    email_with_name = address_with_name(@student)
    tutor_email = address_with_name(@tutor)
    subject = "#{project.unit.name}: Task PDFs ready to view"
    mail(
      { to: email_with_name, subject: subject }.merge(
        outbound_sender_headers(development_from: tutor_email, reply_to: tutor_email)
      )
    )
  end

  def task_feedback_ready(project, tasks)
    return nil if project.nil? || tasks.nil? || tasks.empty?

    add_general
    @student = project.student
    @project = project
    @tasks = tasks.sort_by { |t| t.task_definition.abbreviation }
    @tutor = project.main_convenor_user
    @has_comments = !@tasks.select { |t| t.is_last_comment_by?(@tutor) }.empty?
    return nil if @tutor.nil? || @student.nil?

    email_with_name = address_with_name(@student)
    tutor_email = address_with_name(@tutor)
    subject = "#{project.unit.name}: Feedback ready to review"
    mail(
      { to: email_with_name, subject: subject }.merge(
        outbound_sender_headers(development_from: tutor_email, reply_to: tutor_email)
      )
    )
  end

  def overseer_assessment_failed(project, tasks)
    return nil if project.nil? || tasks.nil? || tasks.empty?

    add_general
    @student = project.student
    @project = project
    @tasks = tasks.sort_by { |t| t.task_definition.abbreviation }
    @tutor = project.main_convenor_user
    return nil if @tutor.nil? || @student.nil?

    email_with_name = address_with_name(@student)
    tutor_email = address_with_name(@tutor)
    subject = "#{project.unit.code} #{project.unit.name}: Automated feedback needs your attention"
    mail(
      { to: email_with_name, subject: subject }.merge(
        outbound_sender_headers(development_from: tutor_email, reply_to: tutor_email)
      )
    )
  end

  def portfolio_ready(project)
    return nil if project.nil?

    add_general

    @student = project.student
    @project = project
    @convenor = project.main_convenor_user

    email_with_name = address_with_name(@student)
    convenor_email = address_with_name(@convenor)
    subject = "#{project.unit.name}: Portfolio ready to review"
    mail(
      { to: email_with_name, subject: subject }.merge(
        outbound_sender_headers(development_from: convenor_email, reply_to: convenor_email)
      )
    )
  end

  def portfolio_failed(project)
    return nil if project.nil?

    add_general

    @student = project.student
    @project = project
    @convenor = project.main_convenor_user

    email_with_name = address_with_name(@student)
    convenor_email = address_with_name(@convenor)
    subject = "#{project.unit.name}: Portfolio failed to compile"
    mail(
      { to: email_with_name, subject: subject }.merge(
        outbound_sender_headers(development_from: convenor_email, reply_to: convenor_email)
      )
    )
  end
end
