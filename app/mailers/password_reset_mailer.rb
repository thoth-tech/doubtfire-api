class PasswordResetMailer < ActionMailer::Base
  def reset_password(user)
    @doubtfire_host = Doubtfire::Application.config.institution[:host]
    @doubtfire_product_name = Doubtfire::Application.config.institution[:product_name]
    
    @user = user
    @reset_url = "#{@doubtfire_host}/#/reset-password?token=#{user.reset_password_token}"
    @expiry_hours = 24
    
    # Set the default from address
    institution_email_domain = Doubtfire::Application.config.institution[:email_domain]
    default_from = "noreply@#{institution_email_domain}"
    
    # Create email with user's name
    email_with_name = %("#{@user.name}" <#{@user.email}>)
    
    mail(
      to: email_with_name,
      from: default_from,
      subject: "[#{@doubtfire_product_name}] Password Reset Request"
    )
  end

  def password_changed(user)
    @doubtfire_host = Doubtfire::Application.config.institution[:host]
    @doubtfire_product_name = Doubtfire::Application.config.institution[:product_name]
    
    @user = user
    
    # Set the default from address
    institution_email_domain = Doubtfire::Application.config.institution[:email_domain]
    default_from = "noreply@#{institution_email_domain}"
    
    # Create email with user's name
    email_with_name = %("#{@user.name}" <#{@user.email}>)
    
    mail(
      to: email_with_name,
      from: default_from,
      subject: "[#{@doubtfire_product_name}] Password Changed Successfully"
    )
  end
end


