module Entities
  module Minimal
    class MinimalUserEntity < Grape::Entity
      expose :id
      expose :email
      expose :first_name
      expose :last_name
      expose :username
      expose :nickname
      expose :display_name
    end
  end
end
