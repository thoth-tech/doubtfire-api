# frozen_string_literal: true

module UnitHub
  class Serializer
    def self.announcement(record)
      record.attributes.slice('id', 'unit_id', 'title', 'body', 'source_url', 'pinned').symbolize_keys.merge(
        unit_code: record.unit.code, unit_name: record.unit.name,
        published_at: record.published_at&.iso8601, expires_at: record.expires_at&.iso8601,
        updated_at: record.updated_at.iso8601, source_provider: record.source_provider,
        managed_externally: record.source_provider == 'microsoft_teams',
        author_name: record.source_provider == 'microsoft_teams' ? 'Teaching team' : nil,
        source_imported_at: record.source_imported_at&.iso8601
      )
    end

    def self.session(record, occurrence = nil)
      values = record.attributes.slice('id', 'unit_id', 'title', 'description', 'kind', 'timezone',
                                       'location', 'join_url', 'source_url', 'published', 'cancelled',
                                       'recurrence').symbolize_keys
      values.merge!(unit_code: record.unit.code, unit_name: record.unit.name,
                    start_at: record.start_at.iso8601, end_at: record.end_at.iso8601,
                    recurrence_until: record.recurrence_until&.iso8601, updated_at: record.updated_at.iso8601)
      if occurrence
        values.merge!(occurrence_id: occurrence[:occurrence_id], original_start_at: record.start_at.iso8601,
                      start_at: occurrence[:start_at].iso8601, end_at: occurrence[:end_at].iso8601)
        values[:join_url] = nil if record.cancelled?
      end
      values
    end
  end
end
