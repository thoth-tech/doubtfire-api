FactoryBot.define do
    factory :feedback_comment_template do

      association :feedback_group
      association :task_status
      sequence(:abbreviation) { |n| "abbreviation-#{n}" }
      sequence(:order)        { |n| n }
      sequence(:chip_text)    { |n| "chip_text-#{n}" }
      sequence(:description)  { |n| "description-#{n}" }
      sequence(:comment_text) { |n| "comment_text-#{n}" }
      sequence(:summary_text) { |n| "summary_text-#{n}" }


    end
end
