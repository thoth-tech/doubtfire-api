# frozen_string_literal: true

require 'test_helper'

class CourseflowTest < ActiveSupport::TestCase
  setup do
    @document = JSON.parse(Rails.root.join('docs/courseflow/sample-catalog.json').read)
    @course = Courseflow::CatalogImporter.import!(@document)
    @user = FactoryBot.create(:user, :student)
  end

  def plan_attributes
    {
      course: @course, user: @user, name: 'Study plan',
      periods: [{ 'year' => 2026, 'trimester' => 1 }, { 'year' => 2026, 'trimester' => 2 }, { 'year' => 2026, 'trimester' => 3 }],
      slots: [
        { 'unit_code' => 'DEMO101', 'year' => 2026, 'trimester' => 1, 'position' => 1 },
        { 'unit_code' => 'DEMO102', 'year' => 2026, 'trimester' => 2, 'position' => 1 },
        { 'unit_code' => 'DEMO201', 'year' => 2026, 'trimester' => 1, 'position' => 2 }
      ]
    }
  end

  def import_invalid_document
    document = @document.deep_dup
    document['version'] = 'invalid-test'
    yield document
    assert_no_difference 'Courseflow::Course.count' do
      assert_raises(ArgumentError, ActiveRecord::RecordInvalid) { Courseflow::CatalogImporter.import!(document) }
    end
  end

  def test_identical_import_is_idempotent_and_changed_version_is_immutable
    assert_no_difference 'Courseflow::Course.count' do
      assert_equal @course.id, Courseflow::CatalogImporter.import!(@document).id
    end
    document = @document.merge('name' => 'Changed curriculum')
    assert_raises(ArgumentError) { Courseflow::CatalogImporter.import!(document) }
    assert_raises(ActiveRecord::RecordInvalid) { @course.update!(units: []) }
    assert_equal @document['name'], @course.reload.name
    document['version'] = 'QA-2027'
    assert_difference 'Courseflow::Course.count', 1 do
      Courseflow::CatalogImporter.import!(document)
    end
  end

  def test_catalog_rejects_unknown_fields_and_untyped_values
    import_invalid_document { |document| document['user_id'] = @user.id }
    import_invalid_document { |document| document['elective_count'] = '1' }
    import_invalid_document { |document| document['name'] = 42 }
    import_invalid_document { |document| document['units'] = nil }
    import_invalid_document { |document| document['units'] = [] }
    import_invalid_document { |document| document['units'][0]['required'] = 'true' }
    import_invalid_document { |document| document['units'][0]['offered_trimesters'] = [1.0] }
    import_invalid_document { |document| document['units'][0]['offered_trimesters'] = [] }
    import_invalid_document { |document| document['units'][0]['prerequisites'] = nil }
  end

  def test_catalog_rejects_duplicate_codes_unknown_prerequisites_cycles_and_impossible_counts
    import_invalid_document { |document| document['units'][2]['code'] = 'DEMO101' }
    import_invalid_document { |document| document['units'][0]['prerequisites'] = ['UNKNOWN'] }
    import_invalid_document { |document| document['units'][0]['prerequisites'] = ['DEMO102'] }
    import_invalid_document { |document| document['units'][0]['prerequisites'] = ['DEMO101'] }
    import_invalid_document { |document| document['elective_count'] = 3 }
    import_invalid_document { |document| document['elective_count'] = -1 }
    import_invalid_document do |document|
      document['units'][0]['prerequisites'] = ['DEMO201']
      document['units'][2]['prerequisites'] = ['DEMO202']
    end
  end

  def test_catalog_rejects_excessive_sizes_before_writing
    import_invalid_document { |document| document['units'] *= 61 }
    import_invalid_document { |document| document['name'] = 'a' * 201 }
    import_invalid_document { |document| document['units'][0]['code'] = 'A' * 21 }
    Tempfile.create(['courseflow-large', '.json']) do |file|
      file.write(' ' * (Courseflow::CatalogImporter::MAX_BYTES + 1))
      file.flush
      assert_raises(ArgumentError) { Courseflow::CatalogImporter.import_file!(file.path) }
    end
  end

  def test_required_prerequisite_chain_must_fit_available_period_limit
    import_invalid_document do |document|
      document['elective_count'] = 0
      document['units'] = (1..61).map do |index|
        { 'code' => "CHAIN#{index}", 'name' => "Chain #{index}", 'required' => true,
          'prerequisites' => index == 1 ? [] : ["CHAIN#{index - 1}"], 'offered_trimesters' => [1, 2, 3] }
      end
    end
  end

  def test_complete_plan_retains_empty_periods_and_returns_no_issues
    map = Courseflow::CourseMap.create!(plan_attributes)
    assert_equal plan_attributes[:periods], map.reload.periods
    assert_empty map.issues
    assert map.as_plan['complete']
    assert_equal 0, map.lock_version
  end

  def test_incomplete_plans_are_saved_and_report_required_elective_and_order_issues
    map = Courseflow::CourseMap.create!(plan_attributes.merge(slots: []))
    assert_equal %w[missing_required missing_required elective_count], map.issues.pluck('code')
    map.slots = [plan_attributes[:slots][1].merge('trimester' => 1)]
    map.save!
    assert_equal %w[missing_required unavailable_trimester prerequisite elective_count], map.issues.pluck('code')
    assert_equal false, map.as_plan['complete']
  end

  def test_prerequisites_must_be_strictly_earlier_and_surplus_electives_are_issues
    map = Courseflow::CourseMap.new(plan_attributes)
    map.slots[0]['trimester'] = 2
    map.slots[0]['position'] = 2
    map.slots << { 'unit_code' => 'DEMO202', 'year' => 2026, 'trimester' => 3, 'position' => 1 }
    map.save!
    assert_equal %w[prerequisite elective_count], map.issues.pluck('code')
    map.slots[0]['year'] = 2025
    map.periods << { 'year' => 2025, 'trimester' => 2 }
    map.save!
    assert_equal ['elective_count'], map.issues.pluck('code')
  end

  def test_invalid_slot_update_preserves_the_entire_saved_plan
    map = Courseflow::CourseMap.create!(plan_attributes)
    before = map.reload.attributes
    map.name = 'Should not save'
    map.periods = [{ 'year' => 2027, 'trimester' => 1 }]
    map.slots = [plan_attributes[:slots][0], plan_attributes[:slots][0]]
    assert_raises(ActiveRecord::RecordInvalid) { map.save! }
    assert_equal before, map.reload.attributes
  end

  def test_stale_model_writes_cannot_overwrite_saved_plan
    map = Courseflow::CourseMap.create!(plan_attributes)
    stale = Courseflow::CourseMap.find(map.id)
    map.update!(name: 'Newest')
    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(name: 'Lost update') }
    assert_raises(ActiveRecord::StaleObjectError) { stale.destroy! }
    assert_equal 'Newest', map.reload.name
  end

  def test_catalog_with_saved_maps_cannot_be_removed_or_edited
    map = Courseflow::CourseMap.create!(plan_attributes)
    assert_raises(ActiveRecord::DeleteRestrictionError) { @course.destroy! }
    assert_raises(ActiveRecord::RecordInvalid) { @course.update!(elective_count: 2) }
    assert_equal @course.id, map.reload.course_id
  end
end
