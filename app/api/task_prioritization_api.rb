require 'grape'

class TaskPrioritizationApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers

  before do
    authenticated?
  end

  desc 'Get prioritised task recommendations for the current student' do
    detail 'Returns a ranked list of tasks across all active enrolled units, ' \
           'scored by deadline urgency, estimated effort, and overall workload.'
  end
  get '/tasks/recommended' do
    results = TaskPrioritizationService.new(current_user).call
    present results
  end
end
