module Entities
  module FeedbackEntities
    class FeedbackCommentEntity < Grape::Entity
      expose :id
      expose :comment
    end
  end
end
