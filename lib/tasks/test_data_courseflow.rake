namespace :db do
  namespace :test_data do
    desc "Creates test data for frontend development including units, prerequisites, and course association."
    task create_frontend_data: :environment do
      puts "Starting to create frontend test data..."

      # 1. Ensure Roles exist (essential for user creation)
      if Role.count == 0
        puts "-> Generating user roles as they don't exist."
        # Simplified role creation based on common roles. Adjust if specific descriptions are needed.
        # This logic is similar to what might be in 'db:init' or an equivalent setup task.
        roles_to_create = [
          { name: 'Student', description: "Students can enroll in units and submit work." },
          { name: 'Tutor', description: "Tutors can supervise tutorials and provide feedback." },
          { name: 'Convenor', description: "Convenors can manage units and act as tutors/students." },
          { name: 'Admin', description: "Admins have full access, can create convenors, etc." },
          { name: 'Auditor', description: "Auditors have read-only admin access." }
        ]
        roles_to_create.each do |role_attrs|
          Role.find_or_create_by!(name: role_attrs[:name]) do |r|
            r.description = role_attrs[:description]
          end
          print "."
        end
        puts " Roles generated."
      else
        puts "Roles already exist."
      end

      # 2. Find or Create a Convenor User
      convenor_role = Role.find_by!(name: 'Convenor')
      admin_role = Role.find_by!(name: 'Admin') # Needed if creating users with system role

      convenor_user = User.find_by(email: 'aconvenor@doubtfire.com')
      unless convenor_user
        puts "Creating a test convenor user..."
        convenor_user = User.create!(
          email: 'testconvenor@example.com',
          username: 'testconvenor',
          login_id: 'testconvenor', # Often same as username
          first_name: 'Test',
          last_name: 'Convenor',
          nickname: 'TestCon',
          system_role: 'Convenor',
          password: 'password',
          password_confirmation: 'password'
        )
        puts "Test convenor user created: #{convenor_user.email}"
      else
        puts "Test convenor user found: #{convenor_user.email}"
      end

      # 3. Find or Create a Teaching Period
      current_year = Date.today.year
      teaching_period = TeachingPeriod.find_or_create_by!(period: 'Trimester 1', year: current_year) do |tp|
        tp.start_date = Date.new(current_year, 3, 1)
        tp.end_date = Date.new(current_year, 6, 30)
        tp.active_until = Date.new(current_year, 7, 31)
        puts "Created Teaching Period: #{tp.period} #{tp.year}"
      end
      puts "Using Teaching Period: #{teaching_period.period} #{teaching_period.year}"

      # 4. Define Unit Data
      puts "Defining unit data..."
      units_data = [
        # 0-Credit Point Compulsory Units
        { code: 'DAI001', name: 'Academic Integrity and Respect at Deakin', credit_points: 0, prerequisites: [] },
        { code: 'STP010', name: 'Career Tools for Employability', credit_points: 0, prerequisites: [] },
        { code: 'SIT010', name: 'Introduction to Online Learning', credit_points: 0, prerequisites: [] },

        # Core Units (12)
        { code: 'SIT102', name: 'Introduction to Programming', credit_points: 1, prerequisites: [] },
        { code: 'SIT111', name: 'Computer Systems', credit_points: 1, prerequisites: [] },
        { code: 'SIT182', name: 'Real World Practices for Cyber Security', credit_points: 1, prerequisites: [] },
        { code: 'SIT112', name: 'Introduction to Data Science and Artificial Intelligence', credit_points: 1, prerequisites: [] },
        { code: 'SIT103', name: 'Database Fundamentals', credit_points: 1, prerequisites: [] },
        { code: 'SIT120', name: 'Introduction to Responsive Web Apps', credit_points: 1, prerequisites: [] },
        { code: 'SIT224', name: 'Information Technology Systems and Innovation', credit_points: 1, prerequisites: [] },
        { code: 'MIS201', name: 'Digital Business Analysis', credit_points: 1, prerequisites: [] },
        { code: 'SIT216', name: 'User-Centered Design', credit_points: 1, prerequisites: [] },
        { code: 'SIT223', name: 'Professional Practice in Information Technology', credit_points: 1, prerequisites: [] },
        { code: 'SIT317', name: 'Information Technology Innovations and Entrepreneurship', credit_points: 1, prerequisites: [] },
        { code: 'SIT328', name: 'Communicating Information Technology Projects', credit_points: 1, prerequisites: ['MIS201'] },

        # Capstone Units
        { code: 'SIT374', name: 'Team Project (A) - Project Management and Practices', credit_points: 1, prerequisites: ['SIT223'] },
        { code: 'SIT344', name: 'Professional Practice', credit_points: 2, prerequisites: ['SIT223'] },
        { code: 'SIT306', name: 'Project Delivery', credit_points: 1, prerequisites: ['SIT374'] }, # Assumed prerequisite
        { code: 'SIT378', name: 'Team Project (B) - Execution and Delivery', credit_points: 1, prerequisites: ['SIT374'] }, # Assumed prerequisite

        # Other Units (for prerequisites and electives)
        { code: 'SIT232', name: 'Object-Orient ed Development', credit_points: 1, prerequisites: ['SIT102'] },
        { code: 'SIT323', name: 'Cloud Native Application Development', credit_points: 1, prerequisites: ['SIT103', 'SIT232'] }
      ]

      created_units_map = {} # To store Unit model instances { unit_code => unit_instance }

      # 5. Create UnitDefinitions and Units
      puts "Creating UnitDefinitions and Units..."
      units_data.each do |unit_data_hash|
        # Create UnitDefinition
        unit_def = UnitDefinition.find_or_create_by!(code: unit_data_hash[:code]) do |ud|
          ud.name = unit_data_hash[:name]
          ud.description = "This unit covers #{unit_data_hash[:name]}. Credit Points: #{unit_data_hash[:credit_points]}."
          ud.version = '1.0'
          puts "Created UnitDefinition: #{ud.code} - #{ud.name}"
        end

        # Find or Create Unit instance
        unit_instance = Unit.find_or_initialize_by(unit_definition_id: unit_def.id, teaching_period: teaching_period)

        # Attributes to set/update
        unit_attributes_to_set = {
          name: unit_def.name,
          code: unit_def.code,
          description: unit_def.description,
          start_date: teaching_period.start_date,
          end_date: teaching_period.end_date,
          active: (teaching_period.active_until > DateTime.now),
          credit_points: unit_data_hash[:credit_points],
          prerequisites: unit_data_hash[:prerequisites].to_json,
          corequisites: unit_data_hash[:corequisites].to_json
        }

        if unit_instance.new_record?
          puts "Creating Unit: #{unit_attributes_to_set[:code]} - #{unit_attributes_to_set[:name]} in #{teaching_period.period} #{teaching_period.year}"
        else
          puts "Updating existing Unit: #{unit_instance.code} in #{teaching_period.period} #{teaching_period.year} with new details."
        end

        unit_instance.assign_attributes(unit_attributes_to_set)
        unit_instance.save! # Save changes for both new and existing records

        # Assign the convenor_user as the main convenor for this unit_instance
        unit_convenor_role = UnitRole.find_or_create_by!(user: convenor_user, unit: unit_instance, role: convenor_role) do |ur|
          puts "Assigned #{convenor_user.username} as Convenor for Unit #{unit_instance.code}"
        end

        # Update the unit with the main_convenor_id if it's not already set or different
        if unit_instance.main_convenor_id != unit_convenor_role.id
          unit_instance.update!(main_convenor_id: unit_convenor_role.id)
          puts "Set main convenor for Unit #{unit_instance.code} to UnitRole ID #{unit_convenor_role.id}"
        end

        created_units_map[unit_data_hash[:code]] = unit_instance
        puts "Processed Unit: #{unit_instance.code}"
      end

      # 6. Find or Create Course S326
        puts "Initialize course S326 by code."
        course_s326 = Courseflow::Course.find_or_create_by!(code: 'S326') do |c|
          c.name = 'Bachelor of Information Technology'
          c.code = 'S326'
          c.year = current_year
          c.version = '1.0'
          c.url = 'https://www.deakin.edu.au/course/bachelor-information-technology'
          puts "Created Course: #{c.code} - #{c.name}"
        end
      puts "Using Course: #{course_s326.code} (ID: #{course_s326.id})"

      # 7. Create Courseflow::CourseMap for Course S326
      # This represents a specific map or plan for the course, associated with a user.
      course_map = Courseflow::CourseMap.find_or_create_by!(courseId: course_s326.id, userId: 1) do |cm|
        # Add any other default attributes for CourseMap if necessary
        puts "Created CourseMap for Course #{course_s326.code} (ID: #{course_s326.id}) and User aadmin (ID: 1)"
      end
      puts "Using CourseMap ID: #{course_map.id} (CourseID: #{course_map.courseId}, UserID: 1)"

      # 8. Create Course Rules and Unit Prerequisites
      puts "\n--- Creating S326 Course Rules ---"

      # Rule: 0-Credit Point Compulsory Units
      compulsory_units = ['DAI001', 'STP010', 'SIT010']
      compulsory_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'compulsory_units',
        description: 'Must pass all 0-credit point compulsory units',
        minimum: 3,
        maximum: 3,
        requirementSetGroupId: 0  # Temporary value
      )
      compulsory_req.update!(requirementSetGroupId: compulsory_req.id)
      compulsory_units.each do |code|
        Courseflow::RequirementSet.create!(
          requirementSetGroupId: compulsory_req.requirementSetGroupId,
          requirementId: compulsory_req.id,
          unitId: created_units_map[code].id,
          description: "Compulsory unit #{code} - #{created_units_map[code].name}"
        )
      end
      puts "CREATED: Rule for 0-credit point compulsory units."

      # Rule: Core Units
      core_units = ['MIS201', 'SIT102', 'SIT103', 'SIT111', 'SIT112', 'SIT120', 'SIT182', 'SIT216', 'SIT223', 'SIT224', 'SIT317', 'SIT328']
      core_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'core_units',
        description: 'Must pass all 12 core units',
        minimum: 12,
        maximum: 12,
        requirementSetGroupId: 0  # Temporary value
      )
      core_req.update!(requirementSetGroupId: core_req.id)
      core_units.each do |code|
        Courseflow::RequirementSet.create!(
          requirementSetGroupId: core_req.requirementSetGroupId,
          requirementId: core_req.id,
          unitId: created_units_map[code].id,
          description: "Core unit #{code} - #{created_units_map[code].name}"
        )
      end
      puts "CREATED: Rule for 12 core units."

      # Rule: Capstone Units (Choice using chained RequirementSets)
      capstone_choice_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'capstone_choice',
        description: 'Must complete ONE capstone option',
        minimum: 1,
        maximum: 1,
        requirementSetGroupId: 0  # Temporary value
      )
      capstone_choice_req.update!(requirementSetGroupId: capstone_choice_req.id)

      # Option A: SIT344 (2cp)
      capstone_option_a_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'capstone_option',
        description: 'Capstone Option A: SIT344 (2cp)',
        requirementSetGroupId: 0  # Temporary value
      )
      capstone_option_a_req.update!(requirementSetGroupId: capstone_option_a_req.id)

      # Option B: SIT306, SIT374, SIT378 (3cp)
      capstone_option_b_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'capstone_option',
        description: 'Capstone Option B: SIT306, SIT374, SIT378',
        minimum: 3,
        maximum: 3,
        requirementSetGroupId: 0  # Temporary value
      )
      capstone_option_b_req.update!(requirementSetGroupId: capstone_option_b_req.id)

      Courseflow::RequirementSet.create!(
        requirementSetGroupId: capstone_option_a_req.id,
        requirementId: capstone_option_a_req.id,
        unitId: created_units_map['SIT344'].id,
        description: "Complete SIT344"
      )
      # RequirementSet for Option B
      ['SIT306', 'SIT374', 'SIT378'].each do |code|
        Courseflow::RequirementSet.create!(
          requirementSetGroupId: capstone_option_b_req.id,
          requirementId: capstone_option_b_req.id,
          unitId: created_units_map[code].id,
          description: "Part of Capstone B"
        )
      end
      # 3. Create the RequirementSet for the main choice. Instead of pointing to units
      # or child groups, it now points directly to the Requirement records for the options.
      Courseflow::RequirementSet.create!(
        requirementSetGroupId: capstone_choice_req.id,
        requirementId: capstone_option_a_req.id, # <-- Points to the Requirement for Option A
        unitId: nil, # <-- This is now valid because of our model change
        description: "Capstone Option A - SIT344 Professional Practice"
      )
      Courseflow::RequirementSet.create!(
        requirementSetGroupId: capstone_choice_req.id,
        requirementId: capstone_option_b_req.id, # <-- Points to the Requirement for Option B
        unitId: nil, # <-- This is now valid
        description: "Capstone Option B - SIT306/SIT374/SIT378 Team Projects"
      )

      puts "CREATED: Rule for Capstone unit choice."

      # Rule: Level Restrictions
      level1_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'level_restriction',
        description: 'Must pass no more than 10 credit points at level 1',
        maximum: 10,
        requirementSetGroupId: 0  # Temporary value
      )
      level1_req.update!(requirementSetGroupId: level1_req.id)

      level3_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'level_restriction',
        description: 'Must pass at least 6 credit points at level 3',
        minimum: 6,
        requirementSetGroupId: 0  # Temporary value
      )
      level3_req.update!(requirementSetGroupId: level3_req.id)
      puts "CREATED: Rules for unit level restrictions."

      # Rule: Total Credit Points
      cp_req = Courseflow::Requirement.create!(
        courseId: course_s326.id,
        type: 'course',
        category: 'credit_points',
        description: 'Must pass 24 credit points for course',
        minimum: 24,
        maximum: 24,
        requirementSetGroupId: 0  # Temporary value
      )
      cp_req.update!(requirementSetGroupId: cp_req.id)
      puts "CREATED: Rule for total course credit points."
      # Create Individual Unit Prerequisites
      puts "\n--- Creating Individual Unit Prerequisites ---"
      units_data.each do |unit_data_hash|
        next if unit_data_hash[:prerequisites].empty?
        target_unit_model = created_units_map[unit_data_hash[:code]]

        requirement = Courseflow::Requirement.find_or_create_by!(
          unitId: target_unit_model.id,
          courseId: course_s326.id,
          type: 'unit',
          category: 'prerequisite',
          description: "Prerequisites for #{target_unit_model.code}",
          requirementSetGroupId: 0
        ) do |req|
          req.minimum = unit_data_hash[:prerequisites].length
          req.maximum = unit_data_hash[:prerequisites].length
        end
        requirement.update!(requirementSetGroupId: requirement.id) if requirement.requirementSetGroupId.nil?

        unit_data_hash[:prerequisites].each do |prereq_code|
          prerequisite_unit_model = created_units_map[prereq_code]
          next unless prerequisite_unit_model
          Courseflow::RequirementSet.find_or_create_by!(
            requirementSetGroupId: requirement.requirementSetGroupId,
            requirementId: requirement.id,
            unitId: prerequisite_unit_model.id,
            description: "Prerequisite #{prereq_code} for #{target_unit_model.code}"
          )
        end
        puts "CREATED: Prerequisites for #{target_unit_model.code}."
      end

      # 9. Define the specific slotting information for units
      unit_specific_slots = {
        'SIT102' => { year_slot: 1, teaching_period_slot: 1, unit_slot: 1 },
        'SIT111' => { year_slot: 1, teaching_period_slot: 1, unit_slot: 2 },
        'SIT182' => { year_slot: 1, teaching_period_slot: 1, unit_slot: 3 },
        'SIT112' => { year_slot: 1, teaching_period_slot: 1, unit_slot: 4 },
        'SIT224' => { year_slot: 1, teaching_period_slot: 2, unit_slot: 1 },
        'SIT103' => { year_slot: 1, teaching_period_slot: 2, unit_slot: 2 },
        'SIT120' => { year_slot: 1, teaching_period_slot: 2, unit_slot: 3 },
        'MIS201' => { year_slot: 1, teaching_period_slot: 2, unit_slot: 4 },
        'SIT216' => { year_slot: 2, teaching_period_slot: 1, unit_slot: 1 },
        'SIT317' => { year_slot: 2, teaching_period_slot: 2, unit_slot: 1 },
        'SIT223' => { year_slot: 2, teaching_period_slot: 2, unit_slot: 2 },
        'SIT374' => { year_slot: 3, teaching_period_slot: 1, unit_slot: 1 },
        'SIT328' => { year_slot: 3, teaching_period_slot: 1, unit_slot: 2 },
        'SIT344' => { year_slot: 3, teaching_period_slot: 2, unit_slot: 3 },
      }

      # 10. Create Courseflow::CourseMapUnit entries for each unit in this CourseMap
      # These entries link the units to the specific course map, effectively defining its content.
      # We'll assign default slotting for demonstration.
      puts "Creating CourseMapUnit entries for CourseMap ID #{course_map.id} based on specific slotting..."
      created_units_map.each_value do |unit_instance|
        slot_info = unit_specific_slots[unit_instance.code]

        if slot_info
          Courseflow::CourseMapUnit.find_or_create_by!(
            courseMapId: course_map.id,
            unitId: unit_instance.id
          ) do |cmu|
            cmu.yearSlot = slot_info[:year_slot]
            cmu.teachingPeriodSlot = slot_info[:teaching_period_slot]
            cmu.unitSlot = slot_info[:unit_slot]
            # Add any other default attributes for CourseMapUnit if necessary
            puts "Created/Found CourseMapUnit for Unit #{unit_instance.code} in CourseMap #{course_map.id} (Y#{cmu.yearSlot}, TP#{cmu.teachingPeriodSlot}, S#{cmu.unitSlot})"
          end
        else
          puts "Skipping CourseMapUnit creation for Unit #{unit_instance.code} as it's not in the specific slotting data."
        end
      end

      puts "Frontend test data creation finished successfully."
    end
  end
end
