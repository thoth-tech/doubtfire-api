class ExtensionComment < TaskComment
  belongs_to :assessor, class_name: 'User', optional: true

  def serialize(user)
    json = super(user)
    json[:granted] = extension_granted
    json[:assessed] = date_extension_assessed.present?
    json[:date_assessed] = date_extension_assessed
    json[:weeks_requested] = extension_weeks
    json[:extension_response] = extension_response
    json[:task_status] = task.status
    json
  end

  def assessed?
    self.date_extension_assessed.present?
  end

  # Make sure we can access super's version of mark_as_read for assess extension
  alias :super_mark_as_read :mark_as_read

  # Allow individual staff and the student to read this... but stop
  # the main tutor reading without assessing. As only the main tutor
  # propagates reads, this will work as required - other staff cant
  # make it read for the main tutor.
  def mark_as_read(user, unit = self.unit)
    super if assessed? || user == project.student || user != recipient
  end

  def assess_extension(user, granted, automatic = false)
    if self.assessed?
      errors.add(:extension, 'could not be applied')
      return false
    end

    can_apply = self.task.can_apply_for_extension?
    should_grant = granted && can_apply

    if should_grant && !self.task.grant_extension(user, extension_weeks)
      errors.add(:extension, 'could not be applied')
      return false
    end

    self.assessor = user
    self.date_extension_assessed = Time.zone.now
    self.extension_granted = should_grant

    should_notify = true

    if self.extension_granted
      if automatic
        self.extension_response = "Time extended to #{self.task.due_date.strftime('%a %b %e')}"
      else
        self.extension_response = "Extension granted to #{self.task.due_date.strftime('%a %b %e')}"
      end
    elsif !can_apply && granted
      self.extension_response = "Extension cannot be granted as deadline has been reached"
      errors.add(:extension, 'cannot be granted as deadline has been reached')
      should_notify = false
    else
      self.extension_response = "Extension rejected"
    end

    # Now make sure to read it by the main tutor - even if assessed by someone else
    super_mark_as_read(project.tutor_for(task.task_definition))
    save!

    if should_notify
      begin
        NotificationService.notify(
          user: project.student,
          type: 'extension',
          event: 'extension_assessed',
          message: extension_response,
          link: "/projects/#{project.id}/dashboard/#{task.task_definition.abbreviation}"
        )
      rescue StandardError => e
        Rails.logger.error "Failed to notify student about extension assessment: #{e.message}"
      end
    end

    true
  end
end
