require 'test_helper'

#
# Contains tests for FeedbackCommentTemplate model objects - not accessed via API
#
class FeedbackCommentTemplateTest < ActiveSupport::TestCase
  # class FeedbackCommentTemplate {
  # 	-string: Abbreviation
  # 	-number: Order
  # 	-char[20]: ChipText
  # 	-string: Description
  # 	-string: CommentText
  # 	-string: SummaryText
  # 	-TaskStatus: TaskStatus
  # }

  # Set up variables for testing
  setup do
    @feedback_group = FactoryBot.create(:feedback_group)

    @abbreviation = Faker::Lorem.word
    @order = Faker::Number.number(digits: 1)
    @chip_text = Faker::Lorem.characters(number: 20)
    @description = Faker::Lorem.sentence
    @comment_text = Faker::Lorem.sentence
    @summary_text = Faker::Lorem.sentence
    # @task_status = FactoryBot.create(:task_status)
  end

  # Test that you can create a valid feedback comment template
  def test_valid_feedback_comment_template_creation
    feedback_comment_template = FeedbackCommentTemplate.create!(feedback_group: @feedback_group, abbreviation: @abbreviation, order: @order, chip_text: @chip_text, description: @description, comment_text: @comment_text, summary_text: @summary_text)

    assert feedback_comment_template.valid?, feedback_comment_template.errors.full_messages
    assert_equal @abbreviation, feedback_comment_template.abbreviation
    assert_equal @order, feedback_comment_template.order
    assert_equal @chip_text, feedback_comment_template.chip_text
    assert_equal @description, feedback_comment_template.description
    assert_equal @comment_text, feedback_comment_template.comment_text
    assert_equal @summary_text, feedback_comment_template.summary_text
  end

  # Test that you cannot create an invalid feedback comment template
  def test_invalid_feedback_comment_template_creation
    # Test that feedback comment template is invalid without abbreviation
    feedback_comment_template = FeedbackCommentTemplate.new(order: @order, chip_text: @chip_text, description: @description, comment_text: @comment_text, summary_text: @summary_text)
    refute feedback_comment_template.valid?, "Feedback comment template is valid without abbreviation"

    # Test that feedback comment template is invalid without order
    feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, chip_text: @chip_text, description: @description, comment_text: @comment_text, summary_text: @summary_text)
    refute feedback_comment_template.valid?, "Feedback comment template is valid without order"

    # Test that feedback comment template is invalid without chip text
    feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, description: @description, comment_text: @comment_text, summary_text: @summary_text)
    refute feedback_comment_template.valid?, "Feedback comment template is valid without chip text"

    # Test that feedback comment template is invalid without description
    feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, comment_text: @comment_text, summary_text: @summary_text)
    refute feedback_comment_template.valid?, "Feedback comment template is valid without description"

    # Test that feedback comment template is invalid without comment text
    feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, description: @description, summary_text: @summary_text)
    refute feedback_comment_template.valid?, "Feedback comment template is valid without comment text"

    # Test that feedback comment template is invalid without summary text
    feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, description: @description, comment_text: @comment_text)
    refute feedback_comment_template.valid?, "Feedback comment template is valid without summary text"

    # Test that feedback comment template is valid with abbreviation, order, chip text, description, comment text, summary text and task status
    feedback_comment_template.feedback_group = @feedback_group
    feedback_comment_template.abbreviation = @abbreviation
    feedback_comment_template.order = @order
    feedback_comment_template.chip_text = @chip_text
    feedback_comment_template.description = @description
    feedback_comment_template.comment_text = @comment_text
    feedback_comment_template.summary_text = @summary_text
    feedback_comment_template.task_status_id = TaskStatus.discuss
    assert feedback_comment_template.valid?, feedback_comment_template.errors.full_messages
  end
end
