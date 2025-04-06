class TutorTime < ApplicationRecord
  belongs_to :user
  belongs_to :task

  validates :user_id, presence: true
  validates :task_id, presence: true
  validates :time_spent, presence: true, numericality: { greater_than_or_equal_to: 0.0 }

  def time_spent_in_hours
    (time_spent.to_f / 60.0).round(2)
  end
end
