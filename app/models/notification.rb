class Notification < ApplicationRecord
  belongs_to :user

  validates :message, presence: true, length: { maximum: 500 }
end
