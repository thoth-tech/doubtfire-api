module Entities
  class UserEntity < Grape::Entity
    expose :id
    expose :student_id, unless: :minimal
    expose :email
    expose :first_name
    expose :last_name
    expose :username
    expose :nickname
    expose :receive_task_notifications, unless: :minimal
    expose :receive_portfolio_notifications, unless: :minimal
    expose :receive_feedback_notifications, unless: :minimal
    expose :display_peer_progress, unless: :minimal
    expose :opt_in_to_research, unless: :minimal
    expose :has_run_first_time_setup, unless: :minimal
    # Theme preference is account-private presentation state. Only endpoints
    # serialising the authenticated account opt in to these fields; shared user
    # lookups must not disclose either the choice or when it was made.
    expose :theme_preference,
           unless: :minimal,
           if: lambda { |user, options|
             options.key?(:theme_owner_id) && user.id.present? && options[:theme_owner_id] == user.id
           }
    expose :theme_preference_updated_at,
           unless: :minimal,
           if: lambda { |user, options|
             options.key?(:theme_owner_id) && user.id.present? && options[:theme_owner_id] == user.id
           }

    expose :accepted_tii_eula, unless: :minimal, if: ->(user, options) { TurnItIn.enabled? } do |user, options|
      if TiiActionFetchFeaturesEnabled.eula_required?
        TurnItIn.eula_version == user.tii_eula_version
      else
        true
      end
    end

    expose :system_role, unless: :minimal do |user, options|
      user.role.name if user.role.present?
    end
  end
end
