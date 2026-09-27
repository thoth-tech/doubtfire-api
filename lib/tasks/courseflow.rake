# frozen_string_literal: true

namespace :courseflow do
  desc 'Import a versioned planning catalog from JSON: courseflow:import[path]'
  task :import, [:path] => :environment do |_task, args|
    abort 'Usage: bundle exec rake "courseflow:import[path/to/catalog.json]"' if args[:path].blank?

    course = Courseflow::CatalogImporter.import_file!(args[:path])
    puts "Imported planning catalog #{course.code} #{course.version} (id #{course.id})"
  rescue JSON::ParserError, ArgumentError, SystemCallError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    abort "Catalog import failed: #{e.message}"
  end
end
