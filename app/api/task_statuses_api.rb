require 'grape'

class TaskStatusesApi < Grape::API
  desc 'Get all the task statuses'
  get '/task_statuses' do
    present TaskStatus.all.order(:id), with: Entities::TaskStatusEntity
  end
end
