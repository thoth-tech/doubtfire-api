require 'test_helper'

#
# Contains tests for FeedbackCommentTemplate model objects - not accessed via API
#
class FeedbackCommentTemplateModelTest < ActiveSupport::TestCase
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
    @abbreviation = Faker::Lorem.word
    @order = Faker::Number.number(digits: 1)
    @chip_text = Faker::Lorem.characters(number: 20)
    @description = Faker::Lorem.sentence
    @comment_text = Faker::Lorem.sentence
    @summary_text = Faker::Lorem.sentence
    @task_status = FactoryBot.create(:task_status)
  end

  # Test that you can create a valid feedback comment template
  def test_valid_feedback_comment_template_creation
    feedback_comment_template = FeedbackCommentTemplate.create!(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, description: @description, comment_text: @comment_text, summary_text: @summary_text, task_status: @task_status)

    assert feedback_comment_template.valid? # "assert": pass if true, i.e. pass if feedback_comment_template exists
    assert_equal @abbreviation, feedback_comment_template.abbreviation
    assert_equal @order, feedback_comment_template.order
    assert_equal @chip_text, feedback_comment_template.chip_text
    assert_equal @description, feedback_comment_template.description
    assert_equal @comment_text, feedback_comment_template.comment_text
    assert_equal @summary_text, feedback_comment_template.summary_text
    assert_equal @task_status, feedback_comment_template.task_status
  end

  # Test that you cannot create an invalid feedback comment template
  def test_invalid_feedback_comment_template_creation

      # Test that feedback comment template is invalid without abbreviation
      feedback_comment_template = FeedbackCommentTemplate.new(order: @order, chip_text: @chip_text, description: @description, comment_text: @comment_text, summary_text: @summary_text, task_status: @task_status)
      refute feedback_comment_template.valid? # pass if feedback

      # Test that feedback comment template is invalid without order
      feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, chip_text: @chip_text, description: @description, comment_text: @comment_text, summary_text: @summary_text, task_status: @task_status)
      refute feedback_comment_template.valid?

      # Test that feedback comment template is invalid without chip text
      feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, description: @description, comment_text: @comment_text, summary_text: @summary_text, task_status: @task_status)
      refute feedback_comment_template.valid?

      # Test that feedback comment template is invalid without description
      feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, comment_text: @comment_text, summary_text: @summary_text, task_status: @task_status)
      refute feedback_comment_template.valid?

      # Test that feedback comment template is invalid without comment text
      feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, description: @description, summary_text: @summary_text, task_status: @task_status)
      refute feedback_comment_template.valid?

      # Test that feedback comment template is invalid without summary text
      feedback_comment_template = FeedbackCommentTemplate.new(abbreviation: @abbreviation, order: @order, chip_text: @chip_text, description: @description, comment_text: @comment_text, task_status: @task_status)
      refute feedback_comment_template.valid?

      # Test that feedback comment template is valid with abbreviation, order, chip text, description, comment text, summary text and task status
      feedback_comment_template.abbreviation = @abbreviation
      feedback_comment_template.order = @order
      feedback_comment_template.chip_text = @chip_text
      feedback_comment_template.description = @description
      feedback_comment_template.comment_text = @comment_text
      feedback_comment_template.summary_text = @summary_text
      feedback_comment_template.task_status = @task_status
      assert feedback_comment_template.valid?

      # Test that the feedback comment template is unsaved
      refute feedback_comment_template.save # fail if feedback_comment_template is saved
  end
end
