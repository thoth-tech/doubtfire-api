require 'test_helper'

class FeedbackGroupTest < ActiveSupport::TestCase

  # Set up variables for testing
  setup do
    @title = Faker::Lorem.sentence
    @feedback_comment_template = FactoryBot.create(:feedback_comment_template)
    @task_definition = FactoryBot.create(:task_definition)
  end

  # Test that you can create a valid feedback group
  def test_valid_feedback_group_creation
    feedback_group = FeedbackGroup.create!(title: @title, feedback_comment_template: @feedback_comment_template, task_definition: @task_definition)

    assert feedback_group.valid? # "assert": pass if true, i.e. pass if feedback_group exists
    assert_equal @title, feedback_group.title
    assert_equal @feedback_comment_template, feedback_group.feedback_comment_template
    assert_equal @task_definition, feedback_group.task_definition
  end

  # Test that you cannot create an invalid feedback group
  def test_invalid_feedback_group_creation

      # Test that feedback group is invalid without title
      feedback_group = FeedbackGroup.new(feedback_comment_template: @feedback_comment_template, task_definition: @task_definition)
      refute feedback_group.valid? # pass if feedback

      # Test that feedback group is invalid without feedback comment template
      feedback_group = FeedbackGroup.new(title: @title, task_definition: @task_definition)
      refute feedback_group.valid?

      # Test that feedback group is invalid without task definition
      feedback_group = FeedbackGroup.new(title: @title, feedback_comment_template: @feedback_comment_template)
      refute feedback_group.valid?

      # Test that feedback group is valid with title, feedback comment template
      # and task definition
      feedback_group.title = @title
      feedback_group.feedback_comment_template = @feedback_comment_template
      feedback_group.task_definition = @task_definition
      assert feedback_group.valid?

      # Test that feedback group is invalid with title and without feedback
      # comment template
      feedback_group.feedback_comment_template = nil
      refute feedback_group.valid?
      assert_includes feedback_group.errors[:feedback_comment_template], "can't be blank"

      # Test that feedback group is invalid with feedback comment template and
      # without title
      feedback_group.title = nil
      feedback_group.feedback_comment_template = @feedback_comment_template
      refute feedback_group.valid?
      assert_includes feedback_group.errors[:title], "can't be blank"

      # Test that feedback group is invalid with title and without task
      # definition
      feedback_group.title = @title
      feedback_group.task_definition = nil
      refute feedback_group.valid?
      assert_includes feedback_group.errors[:task_definition], "can't be blank"

      # Test that feedback group is unsaved
      refute feedback_group.save # fail if feedback_group is saved
  end
end
