module Entities
  class PushSubscriptionEntity < Grape::Entity
    expose :id
    expose :endpoint
    expose :created_at
    expose :updated_at

    # p256dh and auth are deliberately not exposed. They are the browser's own
    # encryption material, the client already holds them, and nothing in the UI
    # needs them read back.
  end
end
