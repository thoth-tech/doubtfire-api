namespace :db do

  desc "check courseflow data"
  task check_courseflow_data: :environment do
    # Check that the unit definitions have been populated
    unit_definitions = UnitDefinition.all
    puts "Unit Definitions: #{unit_definitions.count}"
    unit_definitions.each do |unit_definition|
      puts "Unit Definition: #{unit_definition.name}"
      puts "Description: #{unit_definition.description}"
      puts "Code: #{unit_definition.code}"
      puts "Version: #{unit_definition.version}"
      puts "Units: #{unit_definition.units.count}"
    end
  end

  desc "clear courseflow data"
  task clear_courseflow_data: :environment do
    # Clear existing data from database
    old_units = Unit.where.not(unit_definition_id: nil)
    puts "Deleting #{old_units.count} units"
    old_units.destroy_all
    puts "Deleting #{UnitDefinition.count} unit definitions"
    UnitDefinition.destroy_all
  end

  desc "Populate the courseflow databases with dummy data"
  task populate_courseflow_data: :environment do
    require 'faker'

    # Clear existing data from database
    old_units = Unit.where.not(unit_definition_id: nil)
    puts "Deleting #{old_units.count} units"
    old_units.destroy_all
    puts "Deleting #{UnitDefinition.count} unit definitions"
    UnitDefinition.destroy_all

    unit_names = [
      "Information Technology", "Programming", "Web Development", "Data Science", "Cyber Security"
    ]

    unit_descriptions = [
      "Introduction to Information Technology", "Introduction to Programming", "Introduction to Web Development", "Introduction to Data Science", "Introduction to Cyber Security"
    ]

    course_codes = [
      "SIT101", "SIT102", "SIT103", "SIT104", "SIT105"
    ]

    course_versions = [
      "1.0", "1.1", "1.2", "1.3", "1.4"
    ]

    # Use factorybot to create new unit definitions
    # unit_definitions = FactoryBot.create_list(:unit_definition, 5)
    5.times do
      puts "Creating new unit definitions"
      unit_definition = UnitDefinition.create(
        name: unit_names.sample,
        description: unit_descriptions.sample,
        code: course_codes.sample,
        version: course_versions.sample
      )

      if unit_definition.persisted?
        puts "Unit Definition: #{unit_definition.name}"
        puts "Description: #{unit_definition.description}"
        puts "Code: #{unit_definition.code}"
        puts "Version: #{unit_definition.version}"
        puts "Unit definition #{unit_definition.id} created successfully"

        # Use factory bot to create the associated units
        FactoryBot.create_list(:unit, 3, name: unit_definition.name, description: unit_definition.description, unit_definition_id: unit_definition.id)
      else
        puts "Unit definition not created"
      end
    end

    # Use factory bot to create the associated units
    #unit_definitions.each do |unit_definition|
     # FactoryBot.create_list(:unit, 3, unit_definition_id: unit_definition.id)
    #Send

    puts "Database filled with courseflow data"
    puts "Unit Definitions: #{UnitDefinition.count}"
  end
end
