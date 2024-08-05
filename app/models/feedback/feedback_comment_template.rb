class FeedbackCommentTemplate < ApplicationRecord
  # Associations
  has_and_belongs_to_many :criterion_options

  # Constraints
  validates :comment_text_situation, presence: true
  validates :comment_text_next_action, presence: true
end
