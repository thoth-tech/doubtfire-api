class FeedbackCommentTemplate < ApplicationRecord
  # Associations
  belongs_to :feedback_group
  # belongs_to :task_status, optional: true

  # Validations
  validates :abbreviation, presence: true
  validates :order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :chip_text, length: { maximum: 20 }
  validates :description, :comment_text, :summary_text, presence: true
  # validates :task_status, presence: true
end
