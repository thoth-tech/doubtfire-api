module Courseflow
  class Requirement < ApplicationRecord
    self.inheritance_column = :_type_disabled

    validates :unitId, presence: true, unless: -> { type == 'course' }
    validates :courseId, presence: true
    validates :category, presence: true
    validates :description, presence: true
    validates :requirementSetGroupId, presence: true
  end
end
