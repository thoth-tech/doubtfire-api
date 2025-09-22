require "test_helper"

class TaskDefinitionSelfEnrolmentTest < ActiveSupport::TestCase
  def setup
    @unit = FactoryBot.create(:unit)
    @activity_type = FactoryBot.create(:activity_type)
    @tutorial_stream = FactoryBot.create(:tutorial_stream, unit: @unit, activity_type: @activity_type)
    @tutorial = FactoryBot.create(:tutorial, unit: @unit, tutorial_stream: @tutorial_stream)

    @task_def = FactoryBot.create(:task_definition,
      unit: @unit,
      tutorial_stream: @tutorial_stream,
      tutorial_self_enrolment_enabled: true,
      tutorial_self_enrolment_stream: @tutorial_stream
    )
  end

  test "available_tutorials_for_self_enrolment returns correct tutorials" do
    available = @task_def.available_tutorials_for_self_enrolment
    assert_includes available, @tutorial
    assert_equal 1, available.count
  end

  test "available_tutorials_for_self_enrolment returns none when disabled" do
    @task_def.update!(tutorial_self_enrolment_enabled: false)
    available = @task_def.available_tutorials_for_self_enrolment
    assert_equal 0, available.count
  end

  test "available_tutorials_for_self_enrolment returns none without stream" do
    @task_def.update!(tutorial_self_enrolment_stream: nil)
    available = @task_def.available_tutorials_for_self_enrolment
    assert_equal 0, available.count
  end

  test "only returns tutorials from correct stream" do
    other_stream = FactoryBot.create(:tutorial_stream, unit: @unit, activity_type: @activity_type)
    other_tutorial = FactoryBot.create(:tutorial, unit: @unit, tutorial_stream: other_stream)

    available = @task_def.available_tutorials_for_self_enrolment
    assert_includes available, @tutorial
    assert_not_includes available, other_tutorial
  end
end
