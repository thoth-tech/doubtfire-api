# Read about factories at https://github.com/thoughtbot/factory_bot

FactoryBot.define do

  factory :feedback_group do

    association :task_definition

    transient do # transient: not persisted to database
      number_of_criterion {0} # `0` criteria created unless otherwise specified
      # E.g., "FactoryBot.create(:feedback_group, number_of_criterion: 3)"
    end

    sequence(:order)          { |n| n }
    sequence(:title)          { |n| "feedback_group-#{n}" }
    feedback_comment_template { FactoryBot.create(:feedback_comment_template) }

    # help_text                 { Faker::Lorem.sentence }
    # entry_message             { Faker::Lorem.sentence }
    # exit_message_good         { Faker::Lorem.sentence }
    # exit_message_resubmit     { Faker::Lorem.sentence }

    after(:create) do |feedback_group, evaluator|
      create_list(:criteria, evaluator.number_of_criterion, feedback_group: feedback_group)
    end
  end
end
