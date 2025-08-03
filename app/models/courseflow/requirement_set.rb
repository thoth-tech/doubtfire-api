module Courseflow
  class RequirementSet < ApplicationRecord
    validates :requirementSetGroupId, presence: true
    validates :description, presence: true
    validates :unitId, presence: true, on: :create, unless: -> { unitId.nil? }
    validates :requirementId, presence: true
  end
end
