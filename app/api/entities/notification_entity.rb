module Entities
  class NotificationEntity < Grape::Entity
    expose :id
    expose :notification_type
    expose :message
    expose :link
    expose :read_at
    expose :created_at
  end
end
