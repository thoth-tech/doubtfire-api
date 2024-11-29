class TeacherResponseMailer < ApplicationMailer
  def add_general
    @doubtfire_host = Doubtfire::Application.config.institution[:host]
    @doubtfire_product_name = Doubtfire::Application.config.institution[:product_name]
    @unsubscribe_url = "#{@doubtfire_host}/#/home?notifications"
  end

  def recieved_notification(project, task)
    return nil if project.nil?

    add_general

    @student = project.student
    @project = project
    @convenor = project.main_convenor_user

    email_with_name = %("#{@student.name}" <#{@student.email}>)
    convenor_email = %("#{@convenor.name}" <#{@convenor.email}>)
    subject = "#{project.unit.name} #{task}: You have recieved comments."
    mail(to: email_with_name, from: convenor_email, subject: subject)
  end
end
