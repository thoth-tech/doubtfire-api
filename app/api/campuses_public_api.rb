require 'grape'

class CampusesPublicApi < Grape::API
  helpers AuthenticationHelpers

  before do
    error!({ error: '401 Unauthorized' }, 401) unless authenticated_without_error?
  end
  desc "Get a campus details"
  get '/campuses/:id' do
    campus = Campus.find(params[:id])
    present campus, with: Entities::CampusEntity
  end

  desc 'Get all the Campuses'
  get '/campuses' do
    present Campus.all, with: Entities::CampusEntity
  end
end
