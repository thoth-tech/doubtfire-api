# frozen_string_literal: true

module UnitHub
  # Authorisation is always derived from current enrolments and assigned unit
  # roles. A global staff role alone never opens an unrelated unit's content.
  class Access
    def self.units_for(user)
      student_ids = Project.where(user_id: user.id, enrolled: true).select(:unit_id)
      staff_ids = UnitRole.where(user_id: user.id, role_id: [Role.tutor.id, Role.convenor.id]).select(:unit_id)
      Unit.where(active: true).where(id: student_ids).or(Unit.where(active: true, id: staff_ids))
    end

    def self.manage?(user, unit)
      UnitRole.exists?(user_id: user.id, unit_id: unit.id,
                       role_id: [Role.tutor.id, Role.convenor.id], observer_only: false)
    end
  end
end
