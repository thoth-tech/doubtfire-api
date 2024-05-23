class CriterionOption < ApplicationRecord
  # Associations
  belongs_to :criterion
  belongs_to :task_status
  # has_and_belongs_to_many :feedback_comment_template
  has_many :feedback_comments

  # Constraints
  validates_associated :criterion
end
