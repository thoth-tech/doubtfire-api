require "test_helper"
require "rake"
require "stringio"

class GenerateFeedbackDataTest < ActiveSupport::TestCase
  setup do
    # Load only the relevant tasks into an isolated Rake application.
    @previous_rake_application = Rake.application
    Rake.application = Rake::Application.new

    Rake::Task.define_task(:environment)
    %w[db:drop db:reset db:seed].each do |name|
      Rake::Task.define_task(name)
    end

    load Rails.root.join("lib/tasks/skip_prod.rake").to_s
    load Rails.root.join("lib/tasks/generate_feedback_data.rake").to_s

    @task = Rake::Task["db:generate_feedback_chips"]
  end

  teardown do
    Rake.application = @previous_rake_application
  end

  test "generates chips only for newly created outcomes" do
    unit = Unit.first!
    task_definition = TaskDefinition.first!

    existing_outcome = create(
      :learning_outcome,
      context_type: "Unit",
      context_id: unit.id
    )

    original_outcome_ids = LearningOutcome.pluck(:id)
    original_group_count = Feedback::FeedbackGroupChip
      .where(learning_outcome_id: original_outcome_ids).count
    original_template_count = Feedback::FeedbackTemplateChip
      .where(learning_outcome_id: original_outcome_ids).count

    # Keep this test small while exercising both creation loops.
    Unit.stub(:limit, [unit]) do
      TaskDefinition.stub(:limit, [task_definition]) do
        capture_io { @task.invoke }
      end
    end

    new_outcomes = LearningOutcome.where.not(id: original_outcome_ids)

    assert_equal 6, new_outcomes.count
    assert_equal 3, new_outcomes.where(
      context_type: "Unit", context_id: unit.id
    ).count
    assert_equal 3, new_outcomes.where(
      context_type: "TaskDefinition", context_id: task_definition.id
    ).count

    assert_equal original_group_count,
      Feedback::FeedbackGroupChip.where(
        learning_outcome_id: original_outcome_ids
      ).count

    assert_equal original_template_count,
      Feedback::FeedbackTemplateChip.where(
        learning_outcome_id: original_outcome_ids
      ).count

    assert_equal 0, Feedback::FeedbackGroupChip.where(
      learning_outcome_id: existing_outcome.id
    ).count

    assert_equal 0, Feedback::FeedbackTemplateChip.where(
      learning_outcome_id: existing_outcome.id
    ).count

    new_outcomes.each do |outcome|
      assert_equal 8, Feedback::FeedbackGroupChip.where(
        learning_outcome_id: outcome.id
      ).count

      assert_equal 12, Feedback::FeedbackTemplateChip.where(
        learning_outcome_id: outcome.id
      ).count
    end
  end

  test "production refusal prevents all data generation" do
    original_counts = [
      LearningOutcome.count,
      Feedback::FeedbackGroupChip.count,
      Feedback::FeedbackTemplateChip.count
    ]

    # Simulate the environment check only.
    # The application and database remain booted in test mode.
    simulated_production = ActiveSupport::StringInquirer.new("production")

    Rails.stub(:env, simulated_production) do
      STDIN.stub(:gets, "No\n") do
        capture_io do
          error = assert_raises(RuntimeError) { @task.invoke }

          assert_equal(
            "You chose not to run this in production",
            error.message
          )
        end
      end
    end

    assert_equal original_counts, [
      LearningOutcome.count,
      Feedback::FeedbackGroupChip.count,
      Feedback::FeedbackTemplateChip.count
    ]
  end
end