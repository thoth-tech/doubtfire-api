module Entities
  module FeedbackEntities
    class CriterionOptionEntity < Grape::Entity
      expose :id
      expose :task_status_id
      expose :outcome_status
      expose :resolved_message_text
      expose :unresolved_message_text
    end
  end
end
