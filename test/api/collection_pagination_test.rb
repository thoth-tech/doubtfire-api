require 'test_helper'

class CollectionPaginationTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def assert_page(path, relation, extra = {})
    expected_ids = relation.reorder(id: :asc).pluck(:id)
    get path, extra.merge(page: 2, per_page: 2)
    assert_equal 200, last_response.status, last_response.body
    assert_kind_of Array, last_response_body
    assert_equal expected_ids.drop(2).first(2), last_response_body.map { |row| row['id'] }
    assert_equal expected_ids.length.to_s, last_response.headers['X-Total-Count']
    assert_equal '2', last_response.headers['X-Page']
    assert_equal '2', last_response.headers['X-Per-Page']
    assert_equal ((expected_ids.length + 1) / 2).to_s, last_response.headers['X-Total-Pages']
  end

  def test_existing_staff_lists_are_not_truncated_without_pagination
    FactoryBot.create_list(:user, 51, :convenor)
    add_auth_header_for(user: User.first)

    {'/api/users' => User.all, '/api/users/convenors' => User.convenors,
     '/api/users/tutors' => User.tutors}.each do |path, scope|
      get path
      assert_equal 200, last_response.status
      assert_operator scope.count, :>, 50
      assert_equal scope.pluck(:id).sort, last_response_body.map { |row| row['id'] }.sort
      assert_nil last_response.headers['X-Total-Count']
      assert_page(path, scope)
    end
  end

  def test_public_collections_have_stable_opt_in_pages
    FactoryBot.create_list(:campus, 5)
    FactoryBot.create_list(:activity_type, 5)
    {'/api/campuses' => Campus.all, '/api/activity_types' => ActivityType.all}.each do |path, scope|
      get path
      assert_equal scope.count, last_response_body.length
      assert_page(path, scope)

      get path, page: 2
      assert_equal '50', last_response.headers['X-Per-Page']
      assert_equal scope.reorder(id: :asc).offset(50).pluck(:id), last_response_body.map { |row| row['id'] }

      get path, per_page: 1
      assert_equal [scope.minimum(:id)], last_response_body.map { |row| row['id'] }
      assert_equal '1', last_response.headers['X-Page']

      get path, page: 2_147_483_647, per_page: 500
      assert_equal 200, last_response.status
      assert_empty last_response_body
    end
  end

  def test_bad_public_page_parameters_return_400_instead_of_500
    ['/api/campuses', '/api/activity_types'].each do |path|
      [{page: [1]}, {per_page: [1]}, {page: {number: 1}}, {page: 'abc'},
       {page: 0}, {per_page: -1}, {per_page: 501}, {page: ''},
       {page: 2_147_483_648}].each do |parameters|
        get path, parameters
        assert_equal 400, last_response.status, "#{path} #{parameters.inspect}: #{last_response.body}"
      end
    end
  end

  def test_pagination_does_not_bypass_staff_list_permissions
    add_auth_header_for(user: FactoryBot.create(:user, :student))
    ['/api/users', '/api/users/convenors', '/api/users/tutors', '/api/units'].each do |path|
      get path, page: 1, per_page: 2
      assert_equal 403, last_response.status, path
    end
  end

  def minimal_unit(**attributes)
    FactoryBot.create(:unit, **{
      with_students: false, task_count: 0, tutorials: 0,
      stream_count: 0, outcome_count: 0, staff_count: 0
    }.merge(attributes))
  end

  def test_large_unit_and_project_lists_keep_their_existing_filters
    student = FactoryBot.create(:user, :student)
    51.times { minimal_unit.enrol_student(student, Campus.first) }
    minimal_unit(active: false).enrol_student(student, Campus.first)

    add_auth_header_for(user: User.first)
    get '/api/units'
    assert_equal 200, last_response.status
    assert_equal Unit.where(active: true).pluck(:id).sort, last_response_body.map { |row| row['id'] }.sort
    assert_operator last_response_body.length, :>, 50
    assert_page('/api/units', Unit.all, include_in_active: true)

    add_auth_header_for(user: student)
    get '/api/projects'
    assert_equal 200, last_response.status
    assert_equal 51, last_response_body.length
    assert_equal Project.for_user(student, false).pluck(:id).sort, last_response_body.map { |row| row['id'] }.sort
    get '/api/projects', include_inactive: true
    assert_equal 52, last_response_body.length
    assert_page('/api/projects', Project.for_user(student, true), include_inactive: true, include_task_definitions: true)
  end

  def test_group_pages_remain_scoped_to_the_authorised_group
    unit = minimal_unit(tutorials: 1)
    group_set = FactoryBot.create(:group_set, unit: unit)
    group = FactoryBot.create(:group, group_set: group_set)
    5.times do
      project = unit.enrol_student(FactoryBot.create(:user, :student), Campus.first)
      group.add_member(project)
    end
    path = "/api/units/#{unit.id}/group_sets/#{group_set.id}/groups/#{group.id}/members"
    add_auth_header_for(user: unit.main_convenor_user)
    get path
    assert_equal 200, last_response.status
    assert_equal group.projects.pluck(:id).sort, last_response_body.map { |row| row['id'] }.sort
    assert_page(path, group.projects)
    get path, per_page: [2]
    assert_equal 400, last_response.status

    add_auth_header_for(user: FactoryBot.create(:user, :student))
    get path, page: 1, per_page: 2
    assert_equal 403, last_response.status
    assert_nil last_response.headers['X-Total-Count']
  end

  def test_authenticated_collections_validate_page_parameters
    add_auth_header_for(user: User.first)
    %w[/api/users /api/users/convenors /api/users/tutors /api/units /api/projects].each do |path|
      get path, per_page: [2]
      assert_equal 400, last_response.status, path
      get path, page: -1
      assert_equal 400, last_response.status, path
    end
  end

  def test_empty_project_pages_report_zero_totals
    add_auth_header_for(user: FactoryBot.create(:user, :student))
    get '/api/projects', page: 1, per_page: 2
    assert_equal 200, last_response.status
    assert_empty last_response_body
    assert_equal '0', last_response.headers['X-Total-Count']
    assert_equal '0', last_response.headers['X-Total-Pages']
  end

  def test_browser_clients_can_read_pagination_headers
    get '/api/campuses', {page: 1, per_page: 2}, {'HTTP_ORIGIN' => 'https://client.example'}
    assert_equal 200, last_response.status
    exposed = last_response.headers['Access-Control-Expose-Headers'].to_s.downcase
    %w[x-total-count x-page x-per-page x-total-pages].each { |name| assert_includes exposed, name }
  end
end
