# frozen_string_literal: true

module Courseflow
  # Administrative import only. New curricula always have a new version, even
  # before a student saves a plan, avoiding catalog/map creation races.
  class CatalogImporter
    MAX_BYTES = 1_048_576

    def self.import_file!(path)
      document = File.open(path, 'rb') { |file| file.read(MAX_BYTES + 1) }
      raise ArgumentError, 'Catalog must be at most 1 MiB' if document.bytesize > MAX_BYTES

      import!(JSON.parse(document))
    end

    def self.import!(document)
      validate_shape!(document)
      candidate = Course.new(document)
      Course.transaction do
        existing = Course.find_by(code: candidate.code, version: candidate.version)
        if existing
          raise ArgumentError, 'Catalog version already exists with different data; use a new version' unless existing.as_catalog.except('id') == document

          existing
        else
          candidate.save!
          candidate
        end
      end
    end

    def self.validate_shape!(document)
      unless document.is_a?(Hash) && document.keys.sort == Course::CATALOG_KEYS.sort
        raise ArgumentError, "Catalog must contain exactly #{Course::CATALOG_KEYS.join(', ')}"
      end
      unless %w[code name version].all? { |field| document[field].is_a?(String) && document[field].strip.present? } &&
             document['elective_count'].is_a?(Integer)
        raise ArgumentError, 'Catalog code, name and version must be nonblank strings; elective_count must be an integer'
      end
    end
  end
end
