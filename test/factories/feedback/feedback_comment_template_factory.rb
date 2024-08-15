FactoryBot.define do
  factory :feedback_comment_template do
    abbreviation { Faker::Lorem.word }
    order { Faker::Number.between(from: 1, to: 10) }
    chip_text { Faker::Lorem.characters(number: 10) }
    description { Faker::Lorem.sentence }
    comment_text { Faker::Lorem.paragraph }
    summary_text { Faker::Lorem.sentence }
    feedback_group # This will allow you to pass an existing feedback_group in your test
  end
end
