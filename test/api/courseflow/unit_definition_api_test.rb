require "test_helper"

class UnitDefinitionTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def test_default_create
    unit_definition = FactoryBot.create(:unit_definition)
    assert unit_definition.valid?
    unit_definition.destroy
  end

  def test_specific_create
    unit_definition = FactoryBot.create(:unit_definition, name: 'Introduction to Cyber Security', description: 'An introduction to the fundamental concepts of cyber security.', code: 'SIT101', version: '1.0')
    assert_equal 'Introduction to Cyber Security', unit_definition.name
    assert_equal 'An introduction to the fundamental concepts of cyber security.', unit_definition.description
    assert_equal 'SIT101', unit_definition.code
    assert_equal "1.0", unit_definition.version
    assert unit_definition.valid?
    unit_definition.destroy
  end

  def test_unit_definition_create
    data_to_post = {
      name: 'Introduction to Cyber Security',
      description: 'An introduction to the fundamental concepts of cyber security.',
      code: 'SIT101',
      version: '1.0'
    }
    add_auth_header_for user: User.first
    post_json '/api/unit_definition', data_to_post
    puts last_response.body
    assert_equal 201, last_response.status
  end

  def test_get_unit_definitions
    FactoryBot.create(:unit_definition)
    FactoryBot.create(:unit_definition, name: 'Introduction to Cyber Security', description: 'An introduction to the fundamental concepts of cyber security.', code: 'SIT101', version: '1.0')
    add_auth_header_for user: User.first
    get '/api/unit_definition'
    puts last_response.body
    data = JSON.parse(last_response.body)
    assert_equal 2, data.length
  end

  def test_get_unit_definition_by_id
    unit_definition = FactoryBot.create(:unit_definition)
    add_auth_header_for user: User.first
    get "/api/unit_definition/unitDefinitionId/#{unit_definition.id}"
    puts last_response.body
    data = JSON.parse(last_response.body)
    assert_equal unit_definition.id, data['id']
    assert_equal unit_definition.name, data['name']
    assert_equal unit_definition.description, data['description']
    assert_equal unit_definition.code, data['code']
  end

  def test_get_units_by_unit_definition_id # need to add new table to test the relationship, this can be a temp unit table alternative before migrating the proper table to the new version
    unit_definition = FactoryBot.create(:unit_definition)
    unit = FactoryBot.create(:unit, unit_definition: unit_definition)
    add_auth_header_for user: User.first
    puts "This will fail until we create a new table for units to test for now"
    get "/api/unit_definition/#{unit_definition.id}/units"
    puts last_response.body
    data = JSON.parse(last_response.body)
    assert_equal 1, data.length
    assert_equal unit.id, data.first['id']
    assert_equal unit.name, data.first['name']
    puts "test ended"
  end

  def test_search_filtering
    unit_definition1 = FactoryBot.create(:unit_definition, name: 'Introduction to Cyber Security', code: 'SIT101')
    unit_definition2 = FactoryBot.create(:unit_definition, name: 'Introduction to Data Science', code: 'SIT102')
    add_auth_header_for user: User.first
    get "/api/unit_definition/search?name=Data"
    puts last_response.body
    assert_equal 1, JSON.parse(last_response.body).size
  ensure
    unit_definition1.destroy
    unit_definition2.destroy
  end

  def test_search_filtering_no_filter
    unit_definition1 = FactoryBot.create(:unit_definition, name: 'Introduction to Cyber Security', code: 'SIT101')
    unit_definition2 = FactoryBot.create(:unit_definition, name: 'Introduction to Data Science', code: 'SIT102')
    add_auth_header_for user: User.first
    get "/api/unit_definition/search"
    puts last_response.body
    assert_equal 2, JSON.parse(last_response.body).size
  ensure
    unit_definition1.destroy
    unit_definition2.destroy
  end

  def test_update_valid_unit_definition
    unit_definition = FactoryBot.create(:unit_definition)
    data_to_post = {
      name: 'Introduction to Cyber Security',
      description: 'An introduction to the fundamental concepts of cyber security.',
      code: 'SIT101',
      version: '1.0'
    }
    add_auth_header_for user: User.first
    put_json "/api/unit_definition/unitDefinitionId/#{unit_definition.id}", data_to_post
    puts last_response.body
    assert_equal 200, last_response.status
  end

  def test_update_invalid_unit_definition
    unit_definition = FactoryBot.create(:unit_definition)
    data_to_post = {
      name: nil,
      description: nil,
      code: nil,
      version: nil
    }
    add_auth_header_for user: User.first
    put_json "/api/unit_definition/unitDefinitionId/#{unit_definition.id}", data_to_post
    puts last_response.body
    assert_equal 400, last_response.status
  end

  def test_delete_unit_definition
    unit_definition = FactoryBot.create(:unit_definition)
    add_auth_header_for user: User.first
    delete_json "/api/unit_definition/unitDefinitionId/#{unit_definition.id}"
    puts last_response.body
    assert_equal 0, Courseflow::UnitDefinition.where(id: unit_definition.id).count
    assert_nil Courseflow::UnitDefinition.find_by(id: unit_definition.id)
  end

  def test_delete_non_existent_unit_definition
    add_auth_header_for user: User.first
    delete_json "/api/unit_definition/unitDefinitionId/9999"
    puts last_response.body
    assert_equal 404, last_response.status
  end

  def test_unit_definition_create_unauthorised
    data_to_post = {
      name: 'Introduction to Cyber Security',
      description: 'An introduction to the fundamental concepts of cyber security.',
      code: 'SIT101',
      version: '1.0'
    }
    post_json '/api/unit_definition', data_to_post
    puts last_response.body
    assert_equal 419, last_response.status
  end

  def test_wrong_auth_level
    unit_definition = FactoryBot.create(:unit_definition)
    data_to_post = {
      name: 'Introduction to Cyber Security',
      description: 'An introduction to the fundamental concepts of cyber security.',
      code: 'SIT101',
      version: '1.0'
    }
    add_auth_header_for user: User.last
    put_json "/api/unit_definition/unitDefinitionId/#{unit_definition.id}", data_to_post
    puts last_response.body
    assert_equal 403, last_response.status
  end
end
