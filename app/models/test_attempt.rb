require 'json'
require 'time'

class TestAttempt < ApplicationRecord
  belongs_to :task, optional: false

  has_one :task_definition, through: :task

  has_one :scorm_comment, as: :commentable, dependent: :destroy

  delegate :role_for, to: :task
  delegate :student, to: :task

  validates :task_id, presence: true

  def self.permissions
    student_role_permissions = [
      :update_attempt
      # :review_own_attempt --  depends on task def settings. See specific_permission_hash method
    ]

    tutor_role_permissions = [
      :review_other_attempt,
      :override_success_status,
      :delete_attempt
    ]

    convenor_role_permissions = [
      :review_other_attempt,
      :override_success_status,
      :delete_attempt
    ]

    nil_role_permissions = []

    {
      student: student_role_permissions,
      tutor: tutor_role_permissions,
      convenor: convenor_role_permissions,
      nil: nil_role_permissions
    }
  end

  # Used to adjust the review own attempt permission based on task def setting
  def specific_permission_hash(role, perm_hash, _other)
    result = perm_hash[role] unless perm_hash.nil?
    if result && role == :student && task_definition.scorm_allow_review
      result << :review_own_attempt
    end
    result
  end

  # task
  # t.references :task

  # extra non-cmi metadata
  # t.datetime :attempted_time, null:false
  # t.boolean :terminated, default: false

  # fields that must be synced from cmi data whenever it's updated
  # t.boolean :completion_status, default: false

  # staff owned, and no longer synced from cmi data. See cmi_datamodel= below.
  # t.boolean :success_status, default: false
  # t.float :score_scaled, default: 0

  # scorm datamodel
  # t.text :cmi_datamodel

  after_initialize if: :new_record? do
    self.attempted_time = Time.zone.now
    task = Task.find(self.task_id)
    learner_name = task.project.student.name
    learner_id = task.project.student.student_id

    init_state = {
      "cmi.completion_status": 'not attempted',
      "cmi.entry": 'ab-initio', # init state
      "cmi.objectives._count": '0', # this counter will be managed on the frontend
      "cmi.interactions._count": '0', # this counter will be managed on the frontend
      "cmi.mode": 'normal',
      "cmi.learner_name": learner_name,
      "cmi.learner_id": learner_id
    }
    self.cmi_datamodel = init_state.to_json
  end

  def cmi_datamodel=(data)
    new_data = JSON.parse(data)

    if self.terminated == true
      raise "Terminated entries should not be updated"
    end

    # set cmi.entry to resume if the attempt is in progress
    if new_data['cmi.completion_status'] == 'incomplete'
      new_data['cmi.entry'] = 'resume'
    end

    # IMPORTANT: always sync any model attributes with cmi values here to ensure consistency!
    # attributes derived from cmi keys: completion_status
    self.completion_status = new_data['cmi.completion_status'] == 'completed'

    # success_status and score_scaled are deliberately no longer derived here.
    # The datamodel is posted by the scorm package running in the student's own
    # browser, and this setter is only reachable through the :update_attempt arm
    # of PATCH test_attempts/:id, which only students hold. Deriving the pass and
    # the score from that blob let a student decide their own result, which is
    # what the route already refuses when it is asked for directly.
    # override_success_status is now the only writer of success_status and the
    # route gates it on :override_success_status. Nothing writes score_scaled, so
    # it keeps its 0.0 column default. The datamodel is still stored exactly as
    # it was posted, so the package keeps its runtime state and can resume.

    write_attribute(:cmi_datamodel, new_data.to_json)
  end

  def review
    dm = JSON.parse(self.cmi_datamodel)
    if dm['cmi.completion_status'] != 'completed'
      raise StandardError, 'Cannot review incomplete attempts!'
    end

    # when review is requested change the mode to review
    dm['cmi.mode'] = 'review'
    self[:cmi_datamodel] = dm.to_json
  end

  def override_success_status(new_success_status)
    dm = JSON.parse(self.cmi_datamodel)
    dm['cmi.success_status'] = (new_success_status ? 'passed' : 'failed')
    self[:cmi_datamodel] = dm.to_json
    self.success_status = dm['cmi.success_status'] == 'passed'
    self.save!
    self.update_scorm_comment
  end

  def add_scorm_comment
    comment = ScormComment.create
    comment.task = task
    comment.user = task.tutor
    comment.comment = success_status_description
    comment.recipient = task.student
    comment.commentable = self
    comment.save!

    comment
  end

  def update_scorm_comment
    if self.scorm_comment.present?
      self.scorm_comment.comment = success_status_description
      self.scorm_comment.save!

      return self.scorm_comment
    end

    logger.warn "WARN: Unexpected need to create scorm comment for test attempt: #{self.id}"
    add_scorm_comment
  end

  def success_status_description
    if self.success_status && self.score_scaled == 1
      "Passed without mistakes"
    elsif self.success_status && self.score_scaled < 1
      "Passed"
    else
      "Unsuccessful"
    end
  end
end
