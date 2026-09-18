module Entities
  class TaskStatusEntity < Grape::Entity
    expose :id
    expose :key do |task_status, _options|
      TaskStatus.id_to_key(task_status.id)
    end
    expose :name
    expose :description
  end
end
