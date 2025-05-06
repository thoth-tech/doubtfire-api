module Entities
  class UnitRoleEntity < Grape::Entity
    expose :id
    expose :role do |unit_role, options| unit_role.role.name end

    # Replaced static MinimalUserEntity with conditional branching to prevent students from seeing full staff details (violates least privilege)
    expose :user, using: Entities::UserEntity, if: lambda { |_unit_role, options|
      Entities::UnitEntity.is_staff?(options[:my_role])
    }
    # Used Entities::UnitEntity.is_staff? for permission check to use centralized and reusable RBAC logic
    expose :user, using: Entities::Minimal::MinimalUserEntity, unless: lambda { |_unit_role, options|
      Entities::UnitEntity.is_staff?(options[:my_role])
    }
    expose :unit, using: Entities::Minimal::MinimalUnitEntity, unless: :in_unit
  end
end
