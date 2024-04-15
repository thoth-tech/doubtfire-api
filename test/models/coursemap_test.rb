require 'test_helper'

class CoursemapTest < ActionDispatch::IntegrationTest
  def test_get_course_map_by_user_id
    puts "Testing get course map by user ID"
    user_id = 1
    FactoryBot.create_list(:coursemap, 3, userId: user_id)

    get "/api/coursemap/#{user_id}"
    puts response.body
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  def test_get_course_map_by_course_id
    puts "Testing get course map by course ID"
    course_id = 1
    FactoryBot.create_list(:coursemap, 3, courseId: course_id)

    get "/api/coursemap/#{course_id}"
    puts response.body
    assert_response :success
    assert_equal 3, JSON.parse(response.body).size
  end

  def test_create_course_map
    puts "Testing create course map"
    post "/api/coursemap", params: { userId: 1, courseId: 1 }
    puts response.body
    assert_response :success
    assert Coursemap.exists?(userId: 1, courseId: 1)
  end

  def test_update_course_map
    puts "Testing update course map"
    course_map = FactoryBot.create(:coursemap)
    put "/api/coursemap/#{course_map.id}", params: { userId: 2, courseId: 2 }
    puts response.body
    assert_response :success
    assert_equal 2, Coursemap.find(course_map.id).userId
  end

  def test_delete_course_map_by_id
    puts "Testing delete course map by ID"
    course_map = FactoryBot.create(:coursemap)
    delete "/api/coursemap/#{course_map.id}"
    puts response.body
    assert_response :success
    assert_not Coursemap.exists?(course_map.id)
  end

  def test_delete_course_maps_by_user_id
    puts "Testing delete course maps by user ID"
    user_id = 1
    FactoryBot.create_list(:coursemap, 3, userId: user_id)

    delete "/api/coursemap/user/#{user_id}"
    puts response.body
    assert_equal 0, Coursemap.where(userId: user_id).count
  end
end
