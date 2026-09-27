# frozen_string_literal: true

require 'grape'

# Catalog reads and private student plans. No teaching-unit permissions or IDs.
class CourseflowApi < Grape::API
  helpers AuthenticationHelpers

  rescue_from Grape::Exceptions::InvalidMessageBody do
    Rack::Response.new({ error: 'Plan must contain valid JSON' }.to_json, 422,
                       { 'content-type' => 'application/json', 'cache-control' => 'private, no-store' })
  end

  before do
    authenticated?
    header 'Cache-Control', 'private, no-store'
  end

  helpers do
    def owned_courseflow_map
      Courseflow::CourseMap.where(user_id: current_user.id).find(courseflow_id(params[:id]))
    end

    def courseflow_id(value)
      error!({ error: 'Not found' }, 404) unless /\A[1-9]\d{0,18}\z/.match?(value.to_s)
      value.to_i
    end

    def courseflow_document(update: false)
      request.body.rewind
      raw = request.body.read(Courseflow::CatalogImporter::MAX_BYTES + 1).to_s
      error!({ error: 'Plan exceeds 1 MiB' }, 422) if raw.bytesize > Courseflow::CatalogImporter::MAX_BYTES
      document = JSON.parse(raw)
      keys = %w[course_id name periods slots]
      keys << 'lock_version' if update
      unless document.is_a?(Hash) && document.keys.sort == keys.sort && !params.key?(:user_id)
        error!({ error: "Plan must contain exactly #{keys.join(', ')}; ownership is server assigned" }, 422)
      end
      unless document['course_id'].is_a?(Integer) && document['course_id'].positive? &&
             document['name'].is_a?(String) && document['name'].strip.present? && document['name'].length <= 200
        error!({ error: 'course_id must be a positive integer and name a nonblank string up to 200 characters' }, 422)
      end
      if update && !(document['lock_version'].is_a?(Integer) && document['lock_version'].between?(0, 2_147_483_647))
        error!({ error: 'lock_version must be a nonnegative integer' }, 422)
      end
      document
    rescue JSON::ParserError
      error!({ error: 'Plan must be a JSON object' }, 422)
    end

    def save_courseflow_map!(map)
      map.save!
    rescue ActiveRecord::RecordInvalid => e
      error!({ error: 'Invalid plan', details: e.record.errors.full_messages }, 422)
    rescue ActiveRecord::StaleObjectError
      courseflow_conflict!
    end

    def courseflow_conflict!
      error!({ error: 'This plan changed in another session. Reload it before saving or deleting.' }, 409)
    end
  end

  namespace :courseflow do
    get :courses do
      Courseflow::Course.order(:code, :version, :id).map(&:as_catalog)
    end

    get 'courses/:id' do
      Courseflow::Course.find(courseflow_id(params[:id])).as_catalog
    end

    get :maps do
      Courseflow::CourseMap.where(user_id: current_user.id).includes(:course).order(updated_at: :desc, id: :desc).map(&:as_plan)
    end

    get 'maps/:id' do
      owned_courseflow_map.as_plan
    end

    post :maps do
      document = courseflow_document
      course = Courseflow::Course.find_by(id: document['course_id'])
      error!({ error: 'Selected course does not exist' }, 422) unless course
      map = Courseflow::CourseMap.new(document.merge('user_id' => current_user.id))
      map.course = course
      save_courseflow_map!(map)
      status 201
      map.as_plan
    end

    put 'maps/:id' do
      map = owned_courseflow_map
      document = courseflow_document(update: true)
      map.with_lock do
        courseflow_conflict! unless document['lock_version'] == map.lock_version
        map.assign_attributes(document.except('lock_version'))
        save_courseflow_map!(map)
      end
      map.as_plan
    end

    delete 'maps/:id' do
      map = owned_courseflow_map
      unless params[:lock_version].is_a?(String) && /\A(?:0|[1-9]\d{0,9})\z/.match?(params[:lock_version]) &&
             params[:lock_version].to_i <= 2_147_483_647 && !params.key?(:user_id)
        error!({ error: 'lock_version query parameter must be a nonnegative integer; ownership is server assigned' }, 422)
      end
      map.with_lock do
        courseflow_conflict! unless params[:lock_version].to_i == map.lock_version
        map.destroy!
      end
      status 204
      body false
    end
  end
end
