# frozen_string_literal: true

require 'grape'
require 'time'

class UnitHubApi < Grape::API
  helpers AuthenticationHelpers

  helpers do
    def hub_unit!
      UnitHub::Access.units_for(current_user).find(params[:unit_id])
    end

    def manageable_hub_unit!
      unit = hub_unit!
      error!({ error: 'Only teaching staff assigned to this unit can manage its hub.' }, 403) unless UnitHub::Access.manage?(current_user, unit)
      unit
    end

    def hub_attributes(key, fields, date_fields: [])
      attributes = declared(params, include_missing: false).fetch(key).slice(*fields).to_h.symbolize_keys
      date_fields.each do |field|
        value = attributes[field]
        next unless value

        unless value.match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)
          error!({ error: "#{field} must include an explicit time zone offset." }, 400)
        end
        attributes[field] = Time.iso8601(value)
      rescue ArgumentError
        error!({ error: "#{field} must be a valid ISO 8601 date and time." }, 400)
      end
      attributes
    end

    params :announcement_fields do
      requires :announcement, type: Hash do
        optional :title, type: String
        optional :body, type: String
        optional :source_url, type: String
        optional :pinned, type: Boolean
        optional :published_at, type: String
        optional :expires_at, type: String
      end
    end

    params :session_fields do
      requires :session, type: Hash do
        optional :title, type: String
        optional :description, type: String
        optional :kind, type: String, values: UnitLearningSession::KINDS
        optional :start_at, type: String
        optional :end_at, type: String
        optional :timezone, type: String
        optional :location, type: String
        optional :join_url, type: String
        optional :source_url, type: String
        optional :published, type: Boolean
        optional :cancelled, type: Boolean
        optional :recurrence, type: String, values: UnitLearningSession::RECURRENCES
        optional :recurrence_until, type: Date
      end
    end

    def announcement_attributes
      hub_attributes(:announcement, %i[title body source_url pinned published_at expires_at], date_fields: %i[published_at expires_at])
    end

    def session_attributes
      hub_attributes(:session, %i[title description kind start_at end_at timezone location join_url source_url published cancelled recurrence recurrence_until], date_fields: %i[start_at end_at])
    end
  end

  before do
    authenticated?
    header 'Cache-Control', 'private, no-store'
  end

  desc 'Published announcements and learning sessions for the current user units'
  get '/unit_hub' do
    units = UnitHub::Access.units_for(current_user).order(:code, :id).to_a
    teams_configuration = UnitHub::Teams::Configuration.new
    announcements = UnitAnnouncement.where(unit_id: units.map(&:id)).visible_at(Time.current).includes(:unit).recent_first.limit(101).to_a
    from = 1.day.ago
    to = 90.days.from_now
    schedules = UnitLearningSession.where(unit_id: units.map(&:id), published: true)
                                   .where('start_at <= ?', to)
                                   .where('end_at >= ? OR recurrence_until >= ?', from, from.to_date)
                                   .includes(:unit)
    sessions = schedules.flat_map do |schedule|
      schedule.occurrences(from: from, to: to).map { |occurrence| UnitHub::Serializer.session(schedule, occurrence) }
    end
    sessions.sort_by! { |occurrence| [Time.iso8601(occurrence[:start_at]), occurrence[:occurrence_id]] }

    {
      units: units.map { |unit| { id: unit.id, code: unit.code, name: unit.name, can_manage: UnitHub::Access.manage?(current_user, unit), teams_sync: teams_configuration.configured_for?(unit.id) ? 'configured' : 'not_configured' } },
      announcements: announcements.first(100).map { |record| UnitHub::Serializer.announcement(record) },
      sessions: sessions,
      announcements_truncated: announcements.length > 100,
      window_start: from.iso8601, window_end: to.iso8601
    }
  end

  resource :units do
    route_param :unit_id, type: Integer do
      resource :announcements do
        get do
          scope = manageable_hub_unit!.unit_announcements
          records = scope.where(source_provider: 'manual').or(scope.visible_at(Time.current)).includes(:unit).recent_first
          records.map { |record| UnitHub::Serializer.announcement(record) }
        end

        params { use :announcement_fields }
        post do
          record = manageable_hub_unit!.unit_announcements.create!(announcement_attributes.merge(author: current_user))
          UnitHub::Serializer.announcement(record)
        end

        route_param :id, type: Integer do
          params { use :announcement_fields }
          put do
            record = manageable_hub_unit!.unit_announcements.find(params[:id])
            error!({ error: 'Manage this imported announcement in Teams.' }, 403) if record.source_provider == 'microsoft_teams'
            record.update!(announcement_attributes)
            UnitHub::Serializer.announcement(record)
          end

          delete do
            record = manageable_hub_unit!.unit_announcements.find(params[:id])
            error!({ error: 'Manage this imported announcement in Teams.' }, 403) if record.source_provider == 'microsoft_teams'
            record.destroy!
            { success: true }
          end
        end
      end

      resource :sessions do
        get do
          records = manageable_hub_unit!.unit_learning_sessions.includes(:unit).order(:start_at, :id)
          records.map { |record| UnitHub::Serializer.session(record) }
        end

        params { use :session_fields }
        post do
          record = manageable_hub_unit!.unit_learning_sessions.create!(session_attributes.merge(author: current_user))
          UnitHub::Serializer.session(record)
        end

        route_param :id, type: Integer do
          params { use :session_fields }
          put do
            record = manageable_hub_unit!.unit_learning_sessions.find(params[:id])
            record.update!(session_attributes)
            UnitHub::Serializer.session(record)
          end

          delete do
            # Preserve the UID and schedule so subscribed calendars receive an
            # explicit cancellation instead of retaining an old working join link.
            record = manageable_hub_unit!.unit_learning_sessions.find(params[:id])
            record.update!(cancelled: true)
            { success: true }
          end
        end
      end
    end
  end
end
