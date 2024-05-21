module Courseflow
class CourseMapUnit < ApplicationRecord

  # Validation rules for attributes in the course map unit model
  validates :courseMapId, presence: true
  validates :unitId, presence: true
  validates :yearSlot, presence: true
  validates :teachingPeriodSlot, presence: true # assuming that there is only one entry for each code, not sure if this is the case
  validates :unitSlot, presence: true

end
end
