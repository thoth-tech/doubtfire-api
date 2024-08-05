require 'test_helper'
require 'json'

class StageApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  setup do
    @unit = FactoryBot.create(:unit)
    @data_to_post = {
      title: 'Stage 1',
      order: '1',
      task_definition_id: @unit.task_definitions.first.id
    }
  end

  # Test that a main convenor of the unit can POST a stage
  def test_create_stage_via_post

    user = @unit.main_convenor_user # adds username and auth_token to Header part of request to the server
    add_auth_header_for(user: user)

    stage_count = Stage.count

    post_json '/api/stages', @data_to_post # the post we will be testing
    assert_equal 201, last_response.status, last_response.body # HTTP status code 201 = created

    stage = Stage.last # reads the new stage from the database

    assert_equal @data_to_post[:title], stage.title # checks that the stage title matches what is expected
    assert_equal @data_to_post[:order].to_i, stage.order # checks the stage order matches what is expected
    assert_equal stage_count + 1, Stage.count # checks the stage count has increased by 1
  end

  # Test that a student of the unit cannot POST a stage
  def test_students_cannot_create_stages

    user = @unit.students.first.user

    stage_count = Stage.count
    add_auth_header_for(user: user) # the API request is sent with the student's username and auth_token, to check if the student is allowed to do this

    post_json '/api/stages', @data_to_post

    assert_equal 403, last_response.status, last_response.body # 403 = Forbidden, indicates that the server understands the request but can't provide additional access
    assert_equal stage_count, Stage.count
  end
end
