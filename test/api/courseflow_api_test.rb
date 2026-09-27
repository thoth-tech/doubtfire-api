# frozen_string_literal: true

require 'test_helper'

class CourseflowApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper

  def app
    Rails.application
  end

  setup do
    @course = Courseflow::CatalogImporter.import_file!(Rails.root.join('docs/courseflow/sample-catalog.json'))
    @student = FactoryBot.create(:user, :student)
    @other = FactoryBot.create(:user, :student)
    @map = Courseflow::CourseMap.create!(valid_document.merge('user_id' => @student.id))
    add_auth_header_for(user: @student)
  end

  def valid_document
    {
      'course_id' => @course.id, 'name' => 'My plan',
      'periods' => [{ 'year' => 2026, 'trimester' => 1 }, { 'year' => 2026, 'trimester' => 2 }],
      'slots' => [{ 'unit_code' => 'DEMO101', 'year' => 2026, 'trimester' => 1, 'position' => 1 }]
    }
  end

  def json_request(method, path, document)
    public_send(method, path, JSON.generate(document), { 'CONTENT_TYPE' => 'application/json' })
  end

  def response_body
    JSON.parse(last_response.body)
  end

  def test_student_catalog_access_needs_no_teaching_unit_permission
    get '/api/courseflow/courses'
    assert_equal 200, last_response.status, last_response.body
    assert_equal [@course.as_catalog], response_body
    assert_equal 'private, no-store', last_response.headers['cache-control']
    get "/api/courseflow/courses/#{@course.id}"
    assert_equal @course.as_catalog, response_body
    get '/api/courseflow/courses/not-an-id'
    assert_equal 404, last_response.status
  end

  def test_unauthenticated_requests_cannot_read_or_write
    header 'Auth-Token', nil
    header 'Username', nil
    [[:get, '/courses'], [:get, '/maps'], [:get, "/maps/#{@map.id}"],
     [:post, '/maps'], [:put, "/maps/#{@map.id}"], [:delete, "/maps/#{@map.id}?lock_version=0"]].each do |method, path|
      json_request(method, "/api/courseflow#{path}", valid_document)
      assert_equal 419, last_response.status, "#{method} #{path}: #{last_response.body}"
    end
  end

  def test_every_role_is_scoped_to_its_own_maps_for_all_operations
    other_map = Courseflow::CourseMap.create!(valid_document.merge('user_id' => @other.id))
    get '/api/courseflow/maps'
    assert_equal [@map.id], response_body.pluck('id')
    users = [@other, FactoryBot.create(:user, :tutor), FactoryBot.create(:user, :convenor), FactoryBot.create(:user, :admin)]
    users.each do |user|
      add_auth_header_for(user: user)
      get "/api/courseflow/maps/#{@map.id}"
      assert_equal 404, last_response.status
      json_request(:put, "/api/courseflow/maps/#{@map.id}", valid_document.merge('lock_version' => 0, 'name' => 'Stolen'))
      assert_equal 404, last_response.status
      delete "/api/courseflow/maps/#{@map.id}?lock_version=0"
      assert_equal 404, last_response.status
      get '/api/courseflow/maps'
      assert_equal(user == @other ? [other_map.id] : [], response_body.pluck('id'))
    end
    assert_equal 'My plan', @map.reload.name
  end

  def test_create_save_reload_and_delete_preserve_full_plan
    json_request(:post, '/api/courseflow/maps', valid_document)
    assert_equal 201, last_response.status, last_response.body
    created = response_body
    assert_equal @student.id, Courseflow::CourseMap.find(created['id']).user_id
    assert_equal valid_document['periods'], created['periods']
    assert_equal false, created['complete']
    assert_equal %w[missing_required elective_count], created['issues'].pluck('code')
    update = valid_document.merge('name' => 'Renamed', 'lock_version' => created['lock_version'], 'slots' => [])
    json_request(:put, "/api/courseflow/maps/#{created['id']}", update)
    assert_equal 200, last_response.status, last_response.body
    assert_equal created['lock_version'] + 1, response_body['lock_version']
    get "/api/courseflow/maps/#{created['id']}"
    assert_equal 'Renamed', response_body['name']
    assert_empty response_body['slots']
    assert_equal update['periods'], response_body['periods']
    delete "/api/courseflow/maps/#{created['id']}?lock_version=#{response_body['lock_version']}"
    assert_equal 204, last_response.status, last_response.body
    assert_empty last_response.body
    assert_not Courseflow::CourseMap.exists?(created['id'])
  end

  def test_stale_updates_and_deletes_preserve_newer_plan
    @map.update!(name: 'Newer plan')
    before = @map.reload.attributes
    json_request(:put, "/api/courseflow/maps/#{@map.id}", valid_document.merge('lock_version' => 0, 'slots' => []))
    assert_equal 409, last_response.status, last_response.body
    assert_equal before, @map.reload.attributes
    delete "/api/courseflow/maps/#{@map.id}?lock_version=0"
    assert_equal 409, last_response.status
    assert_equal before, @map.reload.attributes
  end

  def test_client_cannot_assign_ownership_or_change_course
    json_request(:post, '/api/courseflow/maps', valid_document.merge('user_id' => @other.id))
    assert_equal 422, last_response.status
    json_request(:put, "/api/courseflow/maps/#{@map.id}", valid_document.merge('lock_version' => 0, 'user_id' => @other.id))
    assert_equal 422, last_response.status
    document = @course.as_catalog.except('id').merge('version' => 'next')
    other_course = Courseflow::CatalogImporter.import!(document)
    json_request(:put, "/api/courseflow/maps/#{@map.id}", valid_document.merge('lock_version' => 0, 'course_id' => other_course.id))
    assert_equal 422, last_response.status, last_response.body
    assert_equal @course.id, @map.reload.course_id
    assert_equal @student.id, @map.user_id
  end

  def test_query_parameters_cannot_reassign_ownership
    json_request(:post, "/api/courseflow/maps?user_id=#{@other.id}", valid_document)
    assert_equal 422, last_response.status
    json_request(:put, "/api/courseflow/maps/#{@map.id}?user_id=#{@other.id}", valid_document.merge('lock_version' => 0))
    assert_equal 422, last_response.status
    delete "/api/courseflow/maps/#{@map.id}?lock_version=0&user_id=#{@other.id}"
    assert_equal 422, last_response.status
    assert_equal @student.id, @map.reload.user_id
  end

  def test_lock_version_is_mandatory_and_strictly_typed
    [nil, '0', false, -1, 0.5, 2_147_483_648].each do |version|
      json_request(:put, "/api/courseflow/maps/#{@map.id}", valid_document.merge('lock_version' => version))
      assert_equal 422, last_response.status, last_response.body
    end
    json_request(:put, "/api/courseflow/maps/#{@map.id}", valid_document)
    assert_equal 422, last_response.status
    [nil, '-1', '0.5', 'false', '2147483648'].each do |version|
      delete "/api/courseflow/maps/#{@map.id}", version.nil? ? {} : { lock_version: version }
      assert_equal 422, last_response.status, last_response.body
    end
    assert_equal 0, @map.reload.lock_version
  end

  def test_json_primitives_extra_fields_and_coerced_types_are_rejected
    invalid = [nil, [], true, 'plan', 1, valid_document.merge('name' => 42), valid_document.merge('name' => ' '),
               valid_document.merge('course_id' => @course.id.to_s), valid_document.merge('course_id' => @course.id.to_f),
               valid_document.merge('periods' => nil), valid_document.merge('slots' => nil), valid_document.merge('extra' => true)]
    assert_no_difference 'Courseflow::CourseMap.count' do
      invalid.each do |document|
        json_request(:post, '/api/courseflow/maps', document)
        assert_equal 422, last_response.status, "#{document.inspect}: #{last_response.body}"
      end
    end
  end

  def test_nested_structures_unknown_codes_and_duplicate_slots_are_rejected_atomically
    invalid = [
      valid_document.merge('periods' => []),
      valid_document.merge('periods' => [nil]),
      valid_document.merge('periods' => [{ 'year' => '2026', 'trimester' => 1 }]),
      valid_document.merge('periods' => [{ 'year' => 2026.0, 'trimester' => 1 }]),
      valid_document.merge('periods' => [{ 'year' => 2026, 'trimester' => true }]),
      valid_document.merge('periods' => valid_document['periods'] * 2),
      valid_document.merge('slots' => [false]),
      valid_document.merge('slots' => valid_document['slots'] * 2)
    ]
    [{ 'position' => 0 }, { 'position' => '1' }, { 'unit_code' => 'UNKNOWN' },
     { 'trimester' => 3 }, { 'year' => 2201 }, { 'extra' => 'field' }].each do |change|
      invalid << valid_document.merge('slots' => [valid_document['slots'][0].merge(change)])
    end
    before = @map.attributes
    invalid.each do |document|
      json_request(:put, "/api/courseflow/maps/#{@map.id}", document.merge('name' => 'Invalid replacement', 'lock_version' => 0))
      assert_equal 422, last_response.status, last_response.body
      assert_equal before, @map.reload.attributes
    end
  end

  def test_unknown_course_excessive_periods_and_slots_are_rejected
    invalid = [valid_document.merge('course_id' => 9_999_999_999),
               valid_document.merge('name' => 'a' * 201),
               valid_document.merge('periods' => (2000..2060).map { |year| { 'year' => year, 'trimester' => 1 } }),
               valid_document.merge('slots' => valid_document['slots'] * 241)]
    invalid.each do |document|
      json_request(:post, '/api/courseflow/maps', document)
      assert_equal 422, last_response.status, last_response.body
    end
  end

  def test_different_units_cannot_occupy_the_same_position_and_units_cannot_repeat
    collision = valid_document['slots'][0].merge('unit_code' => 'DEMO201')
    repeated_unit = valid_document['slots'][0].merge('position' => 2)
    [collision, repeated_unit].each do |slot|
      document = valid_document.merge('slots' => valid_document['slots'] + [slot])
      json_request(:post, '/api/courseflow/maps', document)
      assert_equal 422, last_response.status, last_response.body
    end
  end

  def test_malformed_json_is_a_client_error
    post '/api/courseflow/maps', '{', { 'CONTENT_TYPE' => 'application/json' }
    assert_equal 422, last_response.status, last_response.body
  end

  def test_empty_body_is_a_client_error
    ['application/json', 'text/plain'].each do |content_type|
      post '/api/courseflow/maps', '', { 'CONTENT_TYPE' => content_type }
      assert_equal 422, last_response.status, "#{content_type}: #{last_response.body}"
    end
    assert_equal 1, Courseflow::CourseMap.count
  end
end
