require "test_helper"

class CourseTest < ActionDispatch::IntegrationTest

  def test_default_create
    course = FactoryBot.create(:course)
    assert course.valid?
    course.destroy
  end

  def test_specific_create
    course = FactoryBot.create(:course, name: 'Bachelor of Cyber Security', code: 'S334', year: 2024, version: '1.0', url: 'http://example.com')
    assert_equal 'Bachelor of Cyber Security', course.name
    assert_equal 'S334', course.code
    assert_equal 2024, course.year
    assert_equal '1.0', course.version
    assert_equal 'http://example.com', course.url
    assert course.valid?
    course.destroy
  end

  def test_duplicate_course_is_not_allowed
    course = FactoryBot.create(:course, name: 'Bachelor of Cyber Security', code: 'S334', year: 2024, version: '1.0', url: 'http://example.com')
    duplicate_course = FactoryBot.build(:course, name: 'Bachelor of Cyber Security', code: 'S334', year: 2024, version: '1.0', url: 'http://example.com')
    assert duplicate_course.invalid?
    course.destroy
    duplicate_course.destroy
  end

  def test_name_presence
    course = FactoryBot.build(:course, name: nil)
    assert course.invalid?
    assert_includes course.errors[:name], "can't be blank"
    course.destroy
  end

  def test_code_presence
    course = FactoryBot.build(:course, code: nil)
    assert course.invalid?
    assert_includes course.errors[:code], "can't be blank"
    course.destroy
  end

  def test_year_presence
    course = FactoryBot.build(:course, year: nil)
    assert course.invalid?
    assert_includes course.errors[:year], "can't be blank"
    course.destroy
  end

  def test_version_presence
    course = FactoryBot.build(:course, version: nil)
    assert course.invalid?
    assert_includes course.errors[:version], "can't be blank"
    course.destroy
  end

  def test_url_presence
    course = FactoryBot.build(:course, url: nil)
    assert course.invalid?
    assert_includes course.errors[:url], "can't be blank"
    course.destroy
  end

  def test_code_uniqueness
    course = FactoryBot.create(:course, code: 'S334')
    duplicate_course = FactoryBot.build(:course, code: 'S334')
    assert duplicate_course.invalid?
    assert_includes duplicate_course.errors[:code], "has already been taken"
    course.destroy
    duplicate_course.destroy
  end

  def test_url_format
    course = FactoryBot.build(:course, url: 'invalid_url')
    assert course.invalid?
    assert_includes course.errors[:url], 'is invalid'
    course.destroy
  end

  def test_name_length
    course = FactoryBot.build(:course, name: 'a' * 251)
    assert course.invalid?
    course.destroy
  end

  def test_code_length
    course = FactoryBot.build(:course, code: 'a' * 11)
    assert course.invalid?
    course.destroy
  end

  def test_search_filtering
    puts "Testing search filtering"
    unit1 = FactoryBot.create(:course, name: 'Bachelor of Data Science', code: 'S379')
    unit2 = FactoryBot.create(:course, name: 'Bachelor of Arts', code: 'A300')
    get "/api/course/search?name=Data"
    response_data = JSON.parse(response.body)
    puts "Response data: #{response_data}"
    assert_equal 1, response_data.size
    assert_equal 'Bachelor of Data Science', response_data[0]['name']
    unit1.destroy
    unit2.destroy
  end

  def test_search_no_parameters
    puts "Testing search with no parameters"
    course1 = FactoryBot.create(:course, name: 'Bachelor of Data Science', code: 'S304', year: 2024, version: '1.0', url: 'http://example.com')
    course2 = FactoryBot.create(:course, name: 'Bachelor of Computer Science', code: 'S364', year: 2024, version: '1.0', url: 'http://example.com')
    course3 = FactoryBot.create(:course, name: 'Bachelor of Arts', code: 'A343', year: 2024, version: '1.0', url: 'http://example.com')
    puts "Course1: #{course1.id} #{course1.name}, Course2: #{course2.id} #{course2.name}, Course3: #{course3.id} #{course3.name}"
    get "/api/course/search"
    puts "Response body: #{response.body}"
    assert_equal 3, JSON.parse(response.body).size
    course1.destroy
    course2.destroy
    course3.destroy
  end

  def test_update_valid_course
    puts "Testing update valid course"
    course = FactoryBot.create(:course)
    puts "Course: #{course.id} #{course.name}"
    put "/api/course/#{course.id}", params: {name: 'New Name', code: course.code, year: course.year, version: course.version, url: course.url}
    puts "Changed Course Name: #{course.id} #{course.name}"
    puts "Response body: #{response.body}"
    assert_equal 200, response.status
    assert_equal 'New Name', Course.find(course.id).name
    course.destroy
  end

  def test_update_invalid_course
    course = FactoryBot.create(:course)
    put "/api/course/#{course.id}", params: { name: ' ', code: course.code, year: course.year, version: course.version, url: course.url }
    assert_equal 400, response.status
    course.destroy
  end

  def test_delete_existing_course
    course = FactoryBot.create(:course, name: 'Test to delete', code: 'todelete')
    delete "/api/course/#{course.id}", params: { id: course.id }
    assert_equal 0, Course.where(id: course.id).count
    assert_nil Course.find_by(id: course.id)
    course.destroy
  end

  def test_delete_non_existent_course
    delete "/api/course/9999"
    assert_equal 404, response.status
  end

end
