require 'test_helper'

class FeedbackGroupTest < ActiveSupport::TestCase

  # Set up variables for testing
  setup do
    @task_definition = FactoryBot.create(:task_definition)
    @title = Faker::Lorem.sentence
    @order = Faker::Number.number(digits: 1)
  end

  # Test that you can create a valid feedback group
  def test_valid_feedback_group_creation
    feedback_group = FeedbackGroup.create!(title: @title, task_definition: @task_definition, order: @order)

    assert feedback_group.valid?
    assert_equal @title, feedback_group.title
    assert_equal @order, feedback_group.order
    assert_equal @task_definition, feedback_group.task_definition
  end

  # Test that you cannot create an invalid feedback group
  def test_invalid_feedback_group_creation
    # Test that feedback group is invalid without task definition id
    feedback_group = FeedbackGroup.new(title: @title, order: @order)
    refute feedback_group.valid?
    assert_includes feedback_group.errors.full_messages, "Task definition must exist"

    # Test that feedback group is invalid without title
    feedback_group = FeedbackGroup.new(task_definition: @task_definition, order: @order)
    refute feedback_group.valid?
    assert_includes feedback_group.errors.full_messages, "Title can't be blank"
  end

  # Test that you can update a feedback group
  def test_feedback_group_update
    feedback_group = FeedbackGroup.create!(title: @title, task_definition: @task_definition, order: @order)
    new_title = Faker::Lorem.sentence
    new_order = Faker::Number.number(digits: 1)

    feedback_group.update(title: new_title, order: new_order)

    assert feedback_group.valid?
    assert_equal new_title, feedback_group.title
    assert_equal new_order, feedback_group.order
  end

  # Test that you can add a feedback comment template to a feedback group
  def test_feedback_comment_template_addition
    feedback_group = FeedbackGroup.create!(title: @title, task_definition: @task_definition, order: @order)
    feedback_comment_template = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)

    assert_includes feedback_group.feedback_comment_templates, feedback_comment_template

    # test that you can add multiple feedback comment templates to a feedback
    # group
    feedback_comment_template2 = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)

    assert_includes feedback_group.feedback_comment_templates, feedback_comment_template2
  end

  # Test that you can remove a feedback comment template from a feedback group
  def test_feedback_comment_template_removal
    feedback_group = FeedbackGroup.create!(title: @title, task_definition: @task_definition, order: @order)
    feedback_comment_template = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)

    assert_includes feedback_group.feedback_comment_templates, feedback_comment_template

    feedback_comment_template.destroy
    refute feedback_group.feedback_comment_templates.include?(feedback_comment_template)

    # test that you can remove one of multiple feedback comment templates from a
    # feedback group
    feedback_comment_template = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)
    feedback_comment_template2 = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)

    # check that both feedback comment templates are in the feedback group
    assert_includes feedback_group.feedback_comment_templates, feedback_comment_template
    assert_includes feedback_group.feedback_comment_templates, feedback_comment_template2

    feedback_comment_template.destroy

    # check that the first feedback comment template is removed from the
    # feedback group
    refute feedback_group.feedback_comment_templates.include?(feedback_comment_template)
    assert_includes feedback_group.feedback_comment_templates, feedback_comment_template2
  end

  # Test that you can delete a feedback group
  def test_feedback_group_deletion
    feedback_group = FeedbackGroup.create!(title: @title, task_definition: @task_definition, order: @order)
    feedback_group.destroy

    assert feedback_group.destroyed?
  end

  # Test that feedback comment templates are destroyed when a feedback group is
  # destroyed
  def feedback_comment_template_destruction
    # test that you can delete a feedback group with multiple feedback comment
    # templates
    feedback_group = FeedbackGroup.create!(title: @title, task_definition: @task_definition, order: @order)
    feedback_comment_template = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)
    feedback_comment_template2 = FactoryBot.create(:feedback_comment_template, feedback_group: feedback_group)

    feedback_group.destroy

    assert feedback_group.destroyed?
    assert feedback_comment_template.destroyed?
    assert feedback_comment_template2.destroyed?
  end

end
