class Notification < ApplicationRecord
  belongs_to :user

  # Only set on a unique-event conflict. Its push retry must leave the caller's
  # older transaction snapshot before reading/updating the winning row again.
  attr_accessor :reserved_from_existing_event

  # What the notification is about: the comment, the task, or whatever record
  # the event happened to. Optional, because a `general` notification points at
  # nothing and because every row raised before this column existed has no
  # target. Polymorphic, because portfolio and extension events do not point at
  # a task.
  belongs_to :notifiable, polymorphic: true, optional: true

  # Notification categories. task, feedback, portfolio and unit_hub map onto the
  # user preference columns in PREFERENCE_FOR_TYPE, so one category toggle gates
  # every delivery channel (in-app, email, push). unit_hub also has email and
  # push opt-ins of its own, see CHANNEL_PREFERENCES_FOR_TYPE.
  TYPES = %w[task feedback portfolio extension general unit_hub].freeze

  # `notification_type` is the category the user's preferences switch on.
  # `event` is the specific thing that happened within that category, e.g.
  # 'task_comment_created'. It is free text so a new event ticket does not have
  # to edit this model, but it is required so every notification can be traced
  # back to the code that raised it.

  # Maps a notification type to the user preference column that gates it.
  # Types without an entry here are always delivered.
  PREFERENCE_FOR_TYPE = {
    'task' => :receive_task_notifications,
    'feedback' => :receive_feedback_notifications,
    'portfolio' => :receive_portfolio_notifications,
    'unit_hub' => :receive_unit_hub_notifications
  }.freeze

  # Categories whose email and push channels are separate opt-ins. The column in
  # PREFERENCE_FOR_TYPE still switches the whole category off, so these only
  # narrow a category that is on. A type without an entry sends on every
  # channel, which is how the older categories have always behaved.
  CHANNEL_PREFERENCES_FOR_TYPE = {
    'unit_hub' => {
      email: :receive_unit_hub_email_notifications,
      push: :receive_unit_hub_push_notifications
    }
  }.freeze

  validates :notification_type, presence: true, inclusion: { in: TYPES }
  validates :event, presence: true, length: { maximum: 255 }
  validates :message, presence: true, length: { maximum: 500 }
  validates :dedupe_key, length: { maximum: 191 }, allow_nil: true

  # Queue the email only once the transaction that created the notification has
  # committed. Several callers raise notifications from inside a transaction,
  # for example a tutorial enrolment being destroyed removes the student from
  # their group, and a worker that picked the job up before the commit could not
  # see the row yet.
  after_commit :queue_email_delivery, on: :create

  before_create do
    self.email_delivery_state = 'pending' if email_delivery_state == 'untracked'
  end

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.zone.now) unless read?
  end

  PROJECT_LINK = %r{\A/projects/(\d+)(?:/|\z)}
  TASK_LINK = %r{\A/projects/\d+/dashboard/([^/]+)}

  TARGET_KEYS = %i[
    unit_id project_id student_id task_definition_id task_definition_abbr task_id comment_id group_id
    announcement_id session_id
  ].freeze

  # The ids a client needs to open the page this notification is about.
  #
  # Worked out when the notification is read, not stored, so a notification
  # raised before these fields existed still gets them, and a record deleted
  # since then comes back as nil rather than as an id that points at nothing.
  # The notifiable is used first, and the link fills in whatever it cannot
  # say, for example the project behind a group change or a new task.
  def target_ids
    @target_ids ||= resolve_target_ids
  end

  STUDENT_FEEDBACK_EVENTS = %w[
    task_comment_created
    task_automated_comment_created
    discussion_request_created
    extension_assessed
  ].freeze
  PORTFOLIO_EVENTS = %w[portfolio_received portfolio_submitted].freeze

  # The in-app page this notification opens, for the person it was sent to.
  #
  # The same decision the web client makes in notification-target.ts, kept here
  # so an email button lands on the page the bell would have opened. A student
  # goes to their own project, staff go to the task inbox or the staff
  # portfolio view. Falls back to link when the ids cannot be worked out, which
  # is also what an email for a deleted record gets.
  def web_path
    ids = target_ids
    return link if ids[:project_id].nil?

    abbreviation = ids[:task_definition_abbr]
    return link if abbreviation.nil? && link.to_s.match?(TASK_LINK)

    ids[:student_id] == user_id ? student_web_path(ids, abbreviation) : staff_web_path(ids, abbreviation)
  end

  private

  def student_web_path(ids, abbreviation)
    project = "/projects/#{ids[:project_id]}"
    return "#{project}/groups" if event == 'group_membership_changed'
    return "#{project}/tutorials" if event == 'tutorial_changed'
    return "#{project}/portfolio" if PORTFOLIO_EVENTS.include?(event) || (notification_type == 'portfolio' && abbreviation.nil?)
    return "#{project}/dashboard" if abbreviation.nil?

    task = "#{project}/dashboard/#{ERB::Util.url_encode(abbreviation)}"
    STUDENT_FEEDBACK_EVENTS.include?(event) ? "#{task}/feedback" : task
  end

  def staff_web_path(ids, abbreviation)
    unit = "/units/#{ids[:unit_id]}"
    if PORTFOLIO_EVENTS.include?(event) || (notification_type == 'portfolio' && abbreviation.nil?)
      return "#{unit}/students/portfolios/#{ids[:project_id]}"
    end
    return "#{unit}/students" if abbreviation.nil?

    "#{unit}/tasks/inbox/#{ids[:student_id]}/#{ERB::Util.url_encode(abbreviation)}?students=all"
  end

  def resolve_target_ids
    ids = TARGET_KEYS.index_with { nil }
    return unit_hub_target_ids(ids) if notifiable_type.in?(UNIT_HUB_NOTIFIABLES)

    comment = notifiable if notifiable.is_a?(TaskComment)
    task = comment ? comment.task : (notifiable if notifiable.is_a?(Task))
    group = notifiable if notifiable.is_a?(Group)
    project = notifiable if notifiable.is_a?(Project)
    project ||= task&.project
    project ||= Project.find_by(id: Regexp.last_match(1)) if link.to_s =~ PROJECT_LINK

    ids[:comment_id] = comment&.id
    ids[:group_id] = group&.id
    return ids if project.nil?

    ids[:project_id] = project.id
    ids[:unit_id] = project.unit_id
    ids[:student_id] = project.user_id

    task_definition = task&.task_definition
    if task_definition.nil? && link.to_s =~ TASK_LINK
      abbreviation = CGI.unescape(Regexp.last_match(1))
      task_definition = project.unit.task_definitions.find_by(abbreviation: abbreviation)
    end
    return ids if task_definition.nil?

    ids[:task_definition_id] = task_definition.id
    ids[:task_definition_abbr] = task_definition.abbreviation
    ids[:task_id] = task&.id || project.tasks.where(task_definition_id: task_definition.id).pick(:id)
    ids
  end

  UNIT_HUB_NOTIFIABLES = %w[UnitAnnouncement UnitLearningSession].freeze

  # A Unit Hub notification opens the hub for its unit, so it only needs the
  # unit and the announcement or session. A deleted record leaves all of them
  # nil, which the web client reads as no longer available.
  def unit_hub_target_ids(ids)
    record = notifiable
    return ids if record.nil?

    ids[:unit_id] = record.unit_id
    key = record.is_a?(UnitAnnouncement) ? :announcement_id : :session_id
    ids[key] = record.id
    ids
  end

  def queue_email_delivery
    NotificationService.queue_email(self)
  end
end
