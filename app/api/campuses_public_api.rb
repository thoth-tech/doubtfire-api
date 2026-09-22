require 'grape'

class CampusesPublicApi < Grape::API
  helpers CollectionPaginationHelpers
  desc "Get a campus details"
  get '/campuses/:id' do
    campus = Campus.find(params[:id])
    present campus, with: Entities::CampusEntity
  end

  desc 'Get all the Campuses'
  params do
    optional :page, type: Integer, values: 1..CollectionPaginationHelpers::MAX_PAGE, allow_blank: false
    optional :per_page, type: Integer, values: 1..CollectionPaginationHelpers::MAX_PER_PAGE, allow_blank: false
  end
  get '/campuses' do
    result = paginate_collection(Campus.all)

    present result, with: Entities::CampusEntity
  end
end
