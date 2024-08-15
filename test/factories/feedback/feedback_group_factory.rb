# Read about factories at https://github.com/thoughtbot/factory_bot

FactoryBot.define do
  factory :feedback_group do
    association :task_definition

    transient do # transient: not persisted to database
      number_of_feedback_comment_templates { 0 } # `0` criteria created unless otherwise specified
      # E.g., "FactoryBot.create(:feedback_group, number_of_criterion: 3)"
    end

    sequence(:order)          { |n| n }
    sequence(:title)          { |n| "feedback_group-#{n}" }

    after(:create) do |feedback_group, evaluator|
      create_list(:feedback_comment_templates, evaluator.number_of_feedback_comment_templates, feedback_group: feedback_group)
    end
  end
end
