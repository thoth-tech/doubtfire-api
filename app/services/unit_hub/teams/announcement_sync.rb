# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'time'

module UnitHub
  module Teams
    class AnnouncementSync
      SCAN_LIMIT = 25
      SNAPSHOT_LIFETIME = 7.days
      SOURCE_HOSTS = %w[teams.microsoft.com teams.cloud.microsoft].freeze

      def initialize(configuration: Configuration.new, client: nil, now: Time.current)
        @configuration = configuration
        @client = client
        @now = now
      end

      def call
        return { status: 'disabled', synced: 0, failed: 0 } unless @configuration.enabled?

        mappings = @configuration.mappings
        @client ||= GraphClient.new(@configuration.credentials)
        result = { status: 'complete', synced: 0, failed: 0 }
        mappings.rotate((@now.to_i / 300) % mappings.length).each do |mapping|
          unit = Unit.find_by(id: mapping.unit_id, active: true)
          next unless unit

          state = TeamsAnnouncementSyncState.create_or_find_by!(mapping_key: mapping.key) { |row| row.unit = unit }
          next if state.next_attempt_at && state.next_attempt_at > @now

          state.update!(last_attempt_at: @now)
          sync_mapping(mapping, unit)
          state.update!(status: 'synced', last_succeeded_at: @now, next_attempt_at: nil)
          result[:synced] += 1
        rescue GraphClient::Throttled => e
          # Persist the provider cooldown across worker processes and cron runs.
          mappings.each do |entry|
            next unless Unit.exists?(id: entry.unit_id, active: true)

            checkpoint = TeamsAnnouncementSyncState.create_or_find_by!(mapping_key: entry.key) { |row| row.unit_id = entry.unit_id }
            checkpoint.update!(status: 'throttled', next_attempt_at: @now + e.retry_after.seconds)
          end
          result[:status] = 'throttled'
          break
        rescue GraphClient::Error => e
          # Revoke visibility atomically even if a provider copy later fails validation.
          # rubocop:disable Rails/SkipsModelValidations
          imported_for(mapping).update_all(published_at: nil) if e.is_a?(GraphClient::AccessDenied) || e.is_a?(GraphClient::MissingMessage)
          # rubocop:enable Rails/SkipsModelValidations
          state.update!(status: 'failed')
          result[:failed] += 1
          Rails.logger.warn('Teams announcement sync failed for a configured mapping.')
        end
        result
      end

      private

      def sync_mapping(mapping, unit)
        @client.messages(mapping).each { |message| import_message(mapping, unit, message) }
        UnitAnnouncement.where(unit_id: unit.id, source_provider: 'microsoft_teams', source_channel_key: channel_key(mapping))
                        .where('source_checked_at IS NULL OR source_checked_at < ?', @now)
                        .order(:source_checked_at, :id).limit(SCAN_LIMIT).each do |record|
          message = @client.message(mapping, record.external_message_id)
          unless message['id'] == record.external_message_id
            raise GraphClient::Error, 'Teams returned an unexpected message.'
          end
          import_message(mapping, unit, message)
        rescue GraphClient::MissingMessage
          record.update!(published_at: nil, source_checked_at: @now)
        end
      end

      def imported_for(mapping)
        UnitAnnouncement.where(unit_id: mapping.unit_id, source_provider: 'microsoft_teams', source_mapping_key: mapping.key)
      end

      def import_message(mapping, unit, message)
        return unless message.is_a?(Hash) && message['id'].is_a?(String) && message['id'].match?(GraphClient::MESSAGE_ID)

        key = Digest::SHA256.hexdigest(JSON.generate([@client.tenant_id, mapping.team_id, mapping.channel_id, message['id']]))
        record = unit.unit_announcements.find_or_initialize_by(external_source_key: key)
        return if record.persisted? && record.source_provider != 'microsoft_teams'

        unless approved_message?(mapping, message) && message['deletedDateTime'].blank?
          record.update!(published_at: nil, source_checked_at: @now) if record.persisted?
          return
        end
        source_url = source_url(message['webUrl'], mapping, message['id'])
        unless source_url
          record.update!(published_at: nil, source_checked_at: @now) if record.persisted?
          return
        end
        updated_at = Time.iso8601(message['lastModifiedDateTime'] || message.fetch('createdDateTime'))
        # Serialize source-version comparison and update for overlapping cron
        # and operator runs. New-record uniqueness is enforced by the database.
        record.with_lock do
          if record.source_updated_at && record.source_updated_at > updated_at
            record.update!(source_checked_at: @now)
          else
            body = plain_text(message.dig('body', 'content'))
            body = 'Open the original announcement in Teams for attached content.' if body.blank?
            subject = plain_text(message['subject'])
            title = (subject.presence || body.lines.first.presence || 'Unit announcement').strip.first(200)
            record.assign_attributes(source_provider: 'microsoft_teams', external_message_id: message['id'],
                                     source_mapping_key: mapping.key, source_channel_key: channel_key(mapping), source_updated_at: updated_at,
                                     source_imported_at: @now, source_checked_at: @now,
                                     title: title, body: body.first(20_000).byteslice(0, 60_000).scrub, source_url: source_url, author_id: nil,
                                     pinned: false, published_at: Time.iso8601(message.fetch('createdDateTime')),
                                     expires_at: @now + SNAPSHOT_LIFETIME)
            record.save!
          end
        end
      rescue ActiveRecord::RecordNotUnique
        attempts ||= 0
        attempts += 1
        retry if attempts <= 1

        Rails.logger.warn('Teams announcement was concurrently imported; it will be checked next run.')
      rescue ArgumentError, KeyError, TypeError, ActiveRecord::RecordInvalid
        # Provider content is never copied into diagnostics.
        Rails.logger.warn('Skipped an invalid Teams announcement.')
      end

      def approved_message?(mapping, message)
        identity = message['channelIdentity']
        return false unless identity.is_a?(Hash) && identity['teamId'].to_s.downcase == mapping.team_id && identity['channelId'] == mapping.channel_id

        sender = message['from']
        sender.is_a?(Hash) && sender['application'].blank? && sender['user'].is_a?(Hash) &&
          mapping.publisher_ids.include?(sender['user']['id'].to_s.downcase) &&
          message['messageType'] == 'message' && message['replyToId'].blank?
      end

      def channel_key(mapping)
        Digest::SHA256.hexdigest(JSON.generate([@client.tenant_id, mapping.team_id, mapping.channel_id]))
      end

      def source_url(value, mapping, message_id)
        return nil unless value.is_a?(String) && value.bytesize <= 2048 && !value.match?(/[[:space:][:cntrl:]]/)

        uri = URI.parse(value)
        return nil unless uri.is_a?(URI::HTTPS) && SOURCE_HOSTS.include?(uri.host) && uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?
        return nil unless URI::DEFAULT_PARSER.unescape(uri.path) == "/l/message/#{mapping.channel_id}/#{message_id}"

        query = URI.decode_www_form(uri.query.to_s).group_by(&:first)
        return nil unless query['groupId']&.length == 1 && query['tenantId']&.length == 1
        return nil unless query['groupId'].first.last.downcase == mapping.team_id && query['tenantId'].first.last.downcase == @client.tenant_id

        "https://teams.microsoft.com/l/message/#{ERB::Util.url_encode(mapping.channel_id)}/#{message_id}?#{URI.encode_www_form(groupId: mapping.team_id, tenantId: @client.tenant_id)}"
      rescue URI::InvalidURIError
        nil
      end

      def plain_text(value)
        html = value.to_s.gsub(%r{</(?:p|div|li|h[1-6])>|<br\s*/?\s*>}i, "\n")
        CGI.unescapeHTML(ActionController::Base.helpers.sanitize(html, tags: [], attributes: []).to_s)
           .gsub(/\r\n?/, "\n").strip
      end
    end
  end
end
