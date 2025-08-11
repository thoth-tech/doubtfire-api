require 'grape'

class ActivityTypesPublicApi < Grape::API
  helpers AuthenticationHelpers

  before do
    error!({ error: '401 Unauthorized' }, 401) unless authenticated_without_error?
  end
  desc "Get an activity type details"
  get '/activity_types/:id' do
    present ActivityType.find(params[:id]), with: Entities::ActivityTypeEntity
  end

  desc 'Get all the activity types'
  get '/activity_types' do
    present ActivityType.all, with: Entities::ActivityTypeEntity
  end
end
