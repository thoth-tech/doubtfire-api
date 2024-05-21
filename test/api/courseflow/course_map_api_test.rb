require 'test_helper'

class CourseMapTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def test_get_course_map_by_user_id
    user_id = 1043
    course_map = FactoryBot.create(:course_map, courseId: 101, userId: user_id)
    get "/api/coursemap/userId/#{user_id}"
    assert_equal 200, last_response.status
  ensure
    course_map.destroy
  end

  def test_get_course_map_by_course_id
    course_id = 6764
    course_map = FactoryBot.create(:course_map, courseId: course_id)
    get "/api/coursemap/courseId/#{course_id}"
    assert_equal 200, last_response.status
  ensure
    course_map.destroy
  end

  def test_create_course_map
    data_to_post = { userId: 1, courseId: 1 }
    post_json "/api/coursemap", data_to_post
    assert_equal 201, last_response.status
  end

  def test_update_course_map
    course_map = FactoryBot.create(:course_map)
    data_to_put = { userId: 2, courseId: 2 }
    put_json "/api/coursemap/courseMapId/#{course_map.id}", data_to_put
    assert_equal 200, last_response.status
  ensure
    course_map.destroy
  end

  def test_delete_course_map_by_id
    course_map = FactoryBot.create(:course_map, userId: 5, courseId: 10)
    delete_json "/api/coursemap/courseMapId/#{course_map.id}"
    assert_equal 0, Courseflow::CourseMap.where(id: course_map.id).count
  ensure
    course_map.destroy
  end

  def test_delete_course_maps_by_user_id
    user_id = 100
    course_map = FactoryBot.create(:course_map, userId: user_id)
    delete_json "/api/coursemap/userId/#{user_id}"
    assert_equal 0, Courseflow::CourseMap.where(id: user_id).count
  ensure
    course_map.destroy
  end
end
