require 'test_helper'

class CourseMapUnitTest < ActionDispatch::IntegrationTest

  def test_get_course_map_units_by_course_map_id
    course_map = FactoryBot.create(:coursemap)
    FactoryBot.create_list(:coursemapunit, 3, courseMapId: course_map.id)

    get "/coursemapunit/#{course_map.id}"
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  def test_create_course_map_unit
    course_map = FactoryBot.create(:coursemap)
    unit = FactoryBot.create(:unit)

    post "/coursemapunit", params: { courseMapId: course_map.id, unitId: unit.id, yearSlot: 2022, teachingPeriodSlot: 1, unitSlot: 1 }
    assert_response :success
    assert CourseMapUnit.exists?(courseMapId: course_map.id, unitId: unit.id, yearSlot: 2022, teachingPeriodSlot: 1, unitSlot: 1)
  end

  def test_update_course_map_unit
    course_map_unit = FactoryBot.create(:coursemapunit)
    put "/coursemapunit/#{course_map_unit.id}", params: { yearSlot: 2023 }
    assert_response :success
    assert_equal 2023, CourseMapUnit.find(course_map_unit.id).yearSlot
  end

  def test_delete_course_map_unit_by_id
    course_map_unit = FactoryBot.create(:coursemapunit)
    delete "/coursemapunit/#{course_map_unit.id}"
    assert_response :success
    assert_not CourseMapUnit.exists?(course_map_unit.id)
  end

  def test_delete_course_map_units_by_course_map_id
    course_map = FactoryBot.create(:coursemap)
    FactoryBot.create_list(:coursemapunit, 3, courseMapId: course_map.id)

    delete "/coursemapunit/#{course_map.id}"
    assert_response :success
    assert_equal 0, CourseMapUnit.where(courseMapId: course_map.id).count
  end
end
