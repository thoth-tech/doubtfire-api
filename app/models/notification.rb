class Notification < ApplicationRecord
  belongs_to :user

  # Notification categories. The first three map onto the existing user
  # preference columns (receive_task/feedback/portfolio_notifications) so that a
  # single category toggle gates every delivery channel (in-app, email, push).
  TYPES = %w[task feedback portfolio extension general].freeze

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
    'portfolio' => :receive_portfolio_notifications
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

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.zone.now) unless read?
  end

  private

  def queue_email_delivery
    NotificationService.queue_email(self)
  end
end
