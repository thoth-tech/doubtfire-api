module Entities
  module Minimal
    class MinimalUnitEntity < Grape::Entity
      format_with(:date_only) do |date|
        date.strftime('%Y-%m-%d')
      end

      expose :code
      expose :id
      expose :name
      expose :my_role do |unit, options|
        role = unit.role_for(options[:user])
        role&.name
      end
      expose :teaching_period_id, expose_nil: false

      with_options(format_with: :date_only) do
        expose :start_date
        expose :end_date
      end

      expose :active
      expose :allow_flexible_dates
      expose :ordered_task_definitions,
             as: :task_definitions,
             using: Entities::TaskDefinitionEntity,
             if: :include_task_definitions
      expose :grade_values
      expose :grade_definitions
    end
  end
end
