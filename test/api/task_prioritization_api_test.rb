require 'test_helper'

class TaskPrioritizationApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods

  def app
    Rails.application
  end

  setup do
    @user = FactoryBot.create(:user, :student)
    @unit = FactoryBot.create(:unit, active: true)
    @project = FactoryBot.create(
      :project, user: @user, unit: @unit, enrolled: true, target_grade: 1
    )
  end

  test 'returns 401 when unauthenticated' do
    get '/api/tasks/recommended'
    assert_equal 401, last_response.status
  end

  test 'returns 200 and an empty array when student has no tasks' do
    get_with_auth '/api/tasks/recommended', user: @user

    assert_equal 200, last_response.status
    assert_equal [], JSON.parse(last_response.body)
  end

  test 'returns prioritised tasks for current student only' do
    create_task(@project, weighting: 10, due_in_days: 2)
    create_task(@project, weighting: 30, due_in_days: 10)

    get_with_auth '/api/tasks/recommended', user: @user

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal 2, body.length

    # Sorted descending by priority_score
    scores = body.map { |t| t['priority_score'] }
    assert_equal scores.sort.reverse, scores
  end

  test 'response items have expected schema' do
    create_task(@project, weighting: 10, due_in_days: 5)

    get_with_auth '/api/tasks/recommended', user: @user
    item = JSON.parse(last_response.body).first

    %w[task_id task_name unit_id project_id deadline_score
       effort_score workload_score priority_score].each do |key|
      assert item.key?(key), "response missing key #{key}"
    end
  end

  private

  def get_with_auth(path, user:)
    token = user.auth_token # whatever the project uses; adjust if needed
    header 'auth_token', token
    get path
  end

  def create_task(project, weighting:, due_in_days:)
    task_definition = FactoryBot.create(
      :task_definition,
      unit: project.unit,
      weighting: weighting,
      due_date: Time.zone.today + due_in_days.days
    )
    FactoryBot.create(:task, project: project, task_definition: task_definition)
  end
end
