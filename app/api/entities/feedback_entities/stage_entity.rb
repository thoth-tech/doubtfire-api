module Entities
  module FeedbackEntities
    class StageEntity < Grape::Entity
      expose :id
      expose :title
      expose :order
      expose :entry_message
      expose :exit_message_good
      expose :exit_message_resubmit
    end
  end
end
