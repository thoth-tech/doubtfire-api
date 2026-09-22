require 'grape'

class ActivityTypesPublicApi < Grape::API
  helpers CollectionPaginationHelpers
  desc "Get an activity type details"
  get '/activity_types/:id' do
    present ActivityType.find(params[:id]), with: Entities::ActivityTypeEntity
  end

  desc 'Get all the activity types'
  params do
    optional :page, type: Integer, values: 1..CollectionPaginationHelpers::MAX_PAGE, allow_blank: false
    optional :per_page, type: Integer, values: 1..CollectionPaginationHelpers::MAX_PER_PAGE, allow_blank: false
  end
  get '/activity_types' do
    result = paginate_collection(ActivityType.all)

    present result, with: Entities::ActivityTypeEntity
  end
end
