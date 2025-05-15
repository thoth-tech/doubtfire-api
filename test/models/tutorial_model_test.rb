require "test_helper"

class TutorialModelTest < ActiveSupport::TestCase

  def test_default_create
    tutorial = FactoryBot.build(:tutorial)
    assert tutorial.valid?, tutorial.errors

    tutorial_stream = FactoryBot.create(:tutorial_stream, unit: tutorial.unit)
    tutorial.tutorial_stream = tutorial_stream
    assert tutorial.valid?, tutorial.errors
    assert_equal tutorial.unit, tutorial_stream.unit
  end

  def test_unit_inconsistency_raises_error
    tutorial = FactoryBot.build(:tutorial)
    assert tutorial.valid?, tutorial.errors

    tutorial_stream = FactoryBot.create(:tutorial_stream)
    tutorial.tutorial_stream = tutorial_stream
    assert tutorial.invalid?
    assert_equal 'Unit should be same as the unit in the associated tutorial stream', tutorial.errors.full_messages.last
  end

  def test_import_from_valid_csv
    # Setup
    unit = FactoryBot.create(:unit)
    tutor_user = FactoryBot.create(:user, role_id: 3) # role_id 3 for tutor
    unit_role = FactoryBot.create(:unit_role, user: tutor_user, unit: unit) # Create the unit_role
    tutorial_stream = FactoryBot.create(:tutorial_stream, unit: unit)

    file = Tempfile.new('tutorials.csv')
    begin
      # Writing the test CSV data
      file.write("code,abbreviation,unit_id,tutor_id,tutorial_stream\n")
      file.write("CODE123,ABBR,#{unit.id},#{tutor_user.id},#{tutorial_stream.name}\n")
      file.rewind

      # Perform the CSV import
      result = Tutorial.import_from_csv(file)

      # Assert the import was successful
      assert_equal 1, result[:success].length, result[:errors].map { |e| e[:message] }.join(", ")
      assert_empty result[:errors], "There should be no errors"

      # Check if the tutorial is correctly created
      tutorial = Tutorial.find_by(code: 'CODE123')
      assert_not_nil tutorial, "Tutorial should be created"
      assert_equal 'ABBR', tutorial.abbreviation, "Tutorial abbreviation should match"
      assert_equal unit.id, tutorial.unit_id, "Tutorial unit should match"

      # Assert that the tutorial's unit_role_id matches the created unit_role
      assert_equal unit_role.id, tutorial.unit_role_id, "Tutorial's unit_role_id should match the created unit_role"
    ensure
      file.close
      file.unlink
    end
  end

  def test_import_with_missing_headers
    # Prepare a CSV content with a missing header (`tutor_id` is missing)
    csv_content = <<~CSV
      code,unit_id
      TUT102,1
    CSV
    # Create a temporary file with the  CSV content
    file = create_tempfile(csv_content)

    result = Tutorial.import_from_csv(file)

    # Assert that no tutorials were successfully imported
    assert_equal 0, result[:success].size

    # Assert that one error was raised due to the missing header
    assert_equal 1, result[:errors].size

    # Assert that the error message contains 'Missing headers', indicating that the import failed
    assert_match /Missing headers/, result[:errors].first[:message]
  ensure
    file.close
    file.unlink
  end

  def test_export_to_csv
    # Ensure no tutorials exist before starting the test
    Tutorial.delete_all

    # Create necessary objects
    unit = FactoryBot.create(:unit)
    unit_role = FactoryBot.create(:unit_role, unit: unit, role_id: 3)  # Ensure this is a tutor role
    tutorial_stream = FactoryBot.create(:tutorial_stream, unit: unit)

    # Create the tutorial, associating it with the unit_role and tutorial_stream
    tutorial = Tutorial.create(
      meeting_day: "Monday",
      meeting_time: "17:30",
      meeting_location: "ATC101",
      unit: unit,
      unit_role: unit_role,
      tutorial_stream: tutorial_stream,
      abbreviation: "ABBR",
      code: "CODE123"
    )

    # Export tutorials to CSV
    csv = Tutorial.export_to_csv
    data = CSV.parse(csv, headers: true)

    # Check that the exported CSV contains the tutorial that was created
    assert_includes data.map { |row| row['code'] }, tutorial.code, "Expected tutorial code to be included in the export"
    assert_includes data.map { |row| row['abbreviation'] }, tutorial.abbreviation, "Expected tutorial abbreviation to be included in the export"
    assert_includes data.map { |row| row['unit_id'] }, tutorial.unit_id.to_s, "Expected tutorial unit_id to be included in the export"
    assert_includes data.map { |row| row['tutor_id'] }, tutorial.unit_role.user_id.to_s, "Expected tutor_id to be included in the export"
  end

  private

  def create_tempfile(content)
    file = Tempfile.new(['test_csv', '.csv'])
    file.write(content)
    file.rewind
    file
  end
end
