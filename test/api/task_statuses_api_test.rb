require 'test_helper'

class TaskStatusesApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  # The endpoint is public, so no auth header is added on purpose.
  def test_get_all_task_statuses
    get '/api/task_statuses'

    assert_equal 200, last_response.status, last_response_body

    body = JSON.parse(last_response.body)
    assert_equal TaskStatus.count, body.length
    assert_equal 15, body.length

    # Every row carries the id, its key, a name and a description, and the key
    # must be the one the model derives for that id.
    body.each do |row|
      assert row.key?('id')
      assert row.key?('key')
      assert row.key?('name')
      assert row.key?('description')
      assert_equal TaskStatus.id_to_key(row['id']).to_s, row['key']
    end

    # Ordered by id ascending.
    ids = body.map { |row| row['id'] }
    assert_equal ids.sort, ids
  end
end
