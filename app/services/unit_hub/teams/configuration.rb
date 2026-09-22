# frozen_string_literal: true

require 'digest'
require 'json'

module UnitHub
  module Teams
    class Configuration
      class Error < StandardError; end
      GUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      CHANNEL_ID = /\A19:[A-Za-z0-9_-]+@thread\.(?:tacv2|skype)\z/
      Mapping = Struct.new(:unit_id, :team_id, :channel_id, :publisher_ids, :key, keyword_init: true)

      def initialize(env = ENV)
        @env = env
      end

      def enabled?
        @env['DF_TEAMS_ANNOUNCEMENTS_ENABLED'] == 'true'
      end

      # Visibility configuration intentionally needs no Graph client secret.
      # Only the worker has access to application credentials.
      def mappings
        return [] unless enabled?

        @mappings ||= parse_mappings
      end

      def visible_mapping_keys
        mappings.map(&:key)
      rescue Error
        []
      end

      def configured_for?(unit_id)
        mappings.any? { |mapping| mapping.unit_id == unit_id }
      rescue Error
        false
      end

      def credentials
        tenant_id = @env['DF_TEAMS_TENANT_ID'].to_s
        client_id = @env['DF_TEAMS_CLIENT_ID'].to_s
        secret = @env['DF_TEAMS_CLIENT_SECRET'].to_s
        unless tenant_id.match?(GUID) && client_id.match?(GUID) && secret.present? && secret.bytesize <= 4096
          raise Error, 'Teams application credentials are missing or invalid.'
        end

        { tenant_id: tenant_id.downcase, client_id: client_id.downcase, client_secret: secret }
      end

      private

      def parse_mappings
        raw = @env['DF_TEAMS_CHANNEL_MAPPINGS'].to_s
        raise Error, 'Teams channel mappings are missing or invalid.' if raw.bytesize > 100_000

        unless @env['DF_TEAMS_TENANT_ID'].to_s.match?(GUID)
          raise Error, 'Teams tenant scope is missing or invalid.'
        end
        values = JSON.parse(raw)
        unless values.is_a?(Array) && values.length.between?(1, 20)
          raise Error, 'Configure between one and twenty Teams channel mappings.'
        end
        result = values.map { |value| parse_mapping(value) }
        identities = result.map { |mapping| [mapping.unit_id, mapping.team_id, mapping.channel_id] }
        raise Error, 'Duplicate Teams channel mapping.' unless identities.uniq.length == identities.length

        result
      rescue JSON::ParserError
        raise Error, 'Teams channel mappings are not valid JSON.'
      end

      def parse_mapping(value)
        unless value.is_a?(Hash) && value['student_visible'] == true &&
               value['unit_id'].is_a?(Integer) && value['unit_id'].positive? &&
               value['team_id'].is_a?(String) && value['team_id'].match?(GUID) &&
               value['channel_id'].is_a?(String) && value['channel_id'].length <= 256 && value['channel_id'].match?(CHANNEL_ID)
          raise Error, 'Each mapping must identify a student-visible unit channel.'
        end
        publishers = value['publisher_ids']
        unless publishers.is_a?(Array) && publishers.length.between?(1, 100) && publishers.all? { |id| id.is_a?(String) && id.match?(GUID) }
          raise Error, 'Each mapping needs an allowlist of approved staff publisher IDs.'
        end
        publishers = publishers.map(&:downcase).uniq.sort
        identity = [@env['DF_TEAMS_TENANT_ID'].downcase, value['unit_id'], value['team_id'].downcase, value['channel_id'], true, publishers]
        Mapping.new(unit_id: value['unit_id'], team_id: value['team_id'].downcase,
                    channel_id: value['channel_id'], publisher_ids: publishers,
                    key: Digest::SHA256.hexdigest(JSON.generate(identity)))
      end
    end
  end
end
