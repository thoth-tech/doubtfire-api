require 'grape'

class TutorialsApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers
  helpers MimeCheckHelpers

  before do
    authenticated?
  end

  desc 'Update a tutorial'
  params do
    requires :id, type: Integer, desc: 'The user id to update'
    requires :tutorial, type: Hash do
      optional :abbreviation, type: String, desc: 'The tutorials code'
      optional :meeting_location, type: String,   desc: 'The tutorials location'
      optional :meeting_day, type: String, desc: 'Day of the tutorial'
      optional :tutor_id, type: Integer, desc: 'Id of the tutor'
      optional :campus_id, type: Integer, desc: 'Id of the campus'
      optional :capacity, type: Integer, desc: 'Capacity of the tutorial'
      optional :meeting_time, type: String, desc: 'Time of the tutorial'
    end
  end
  put '/tutorials/:id' do
    tutorial = Tutorial.find(params[:id])
    tut_params = params[:tutorial]
    # can only modify if current_user.id is same as :id provided
    # (i.e., user wants to update their own data) or if update_user token
    unless authorise? current_user, tutorial.unit, :add_tutorial
      error!({ error: "Cannot update tutorial with id=#{params[:id]} - not authorised" }, 403)
    end

    tutorial_parameters = ActionController::Parameters.new(params)
                                                      .require(:tutorial)
                                                      .permit(
                                                        :abbreviation,
                                                        :meeting_location,
                                                        :meeting_day,
                                                        :meeting_time,
                                                        :campus_id,
                                                        :capacity
                                                      )

    if tut_params[:tutor_id]
      tutor = User.find(tut_params[:tutor_id])
      tutorial.assign_tutor(tutor)
    end

    if tutorial_parameters[:campus_id] == -1
      tutorial_parameters[:campus_id] = nil
    end

    tutorial.update!(tutorial_parameters)
    present tutorial, with: Entities::TutorialEntity
  end

  desc 'Create tutorial'
  params do
    requires :tutorial, type: Hash do
      requires :unit_id,              type: Integer,  desc: 'Id of the unit'
      requires :tutor_id,             type: Integer,  desc: 'Id of the tutor'
      optional :campus_id,            type: Integer,  desc: 'Id of the campus',                               allow_blank: true
      requires :capacity,             type: Integer,  desc: 'Capacity of the tutorial',                       allow_blank: false
      requires :abbreviation,         type: String,   desc: 'The tutorials code',                             allow_blank: false
      requires :meeting_location,     type: String,   desc: 'The tutorials location',                         allow_blank: false
      requires :meeting_day,          type: String,   desc: 'Day of the tutorial',                            allow_blank: false
      requires :meeting_time,         type: String,   desc: 'Time of the tutorial',                           allow_blank: false
      optional :tutorial_stream_abbr, type: String,   desc: 'Abbreviation of the associated tutorial stream', allow_blank: false
    end
  end
  post '/tutorials' do
    tut_params = params[:tutorial]
    unit = Unit.find(tut_params[:unit_id])

    unless authorise? current_user, unit, :add_tutorial
      error!({ error: 'Not authorised to create new tutorials' }, 403)
    end

    tutor = User.find(tut_params[:tutor_id])
    campus = tut_params[:campus_id].nil? || tut_params[:campus_id] == -1 ? nil : Campus.find(tut_params[:campus_id])

    # Set Tutorial Stream if available
    tutorial_stream_abbr = tut_params[:tutorial_stream_abbr]
    tutorial_stream = unit.tutorial_streams.find_by!(abbreviation: tutorial_stream_abbr) unless tutorial_stream_abbr.nil?

    tutorial = unit.add_tutorial(tut_params[:meeting_day], tut_params[:meeting_time], tut_params[:meeting_location], tutor, campus, tut_params[:capacity], tut_params[:abbreviation], tutorial_stream)

    present tutorial, with: Entities::TutorialEntity
  end

  desc 'Delete a tutorial'
  params do
    requires :id, type: Integer, desc: 'The tutorial id to delete'
  end
  delete '/tutorials/:id' do
    tutorial = Tutorial.find(params[:id])

    unless authorise? current_user, tutorial.unit, :add_tutorial
      error!({ error: 'Cannot delete tutorial - not authorised' }, 403)
    end

    tutorial.destroy!
    present true, with: Grape::Presenters::Presenter
  end

  desc 'Upload CSV with tutorials'
  params do
    requires :file, type: File, desc: 'CSV upload file.'
  end
  post '/csv/tutorials/upload' do
    unless authorise? current_user, User, :upload_csv
      error!({ error: 'Not authorised to upload CSV of students of tutorials' }, 403)
    end

    if params[:file].blank?
      error!({ error: 'No file uploaded' }, 403)
    end

    if params[:file][:tempfile].size > 5.megabytes
      error!({ error: 'CSV file size exceeds the 5MB limit' }, 413)
    end

    path = params[:file][:tempfile].path
    Tutorial.import_from_csv(File.new(path))
  end

  desc 'Download CSV with tutorials'
  get '/csv/tutorials/download' do
    unless authorise? current_user, User, :download_tutorial_csv
      error!({ error: 'Not authorised to download CSV of all tutorials' }, 403)
    end

    content_type 'application/octet-stream'
    header['Content-Disposition'] = 'attachment; filename=tutorials.csv'
    header['Access-Control-Expose-Headers'] = 'Content-Disposition'
    env['api.format'] = :binary
    Tutorial.export_to_csv
  end
end
