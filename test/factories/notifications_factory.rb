FactoryBot.define do
  factory :notification do
    association :user
    sequence(:message) { |n| "Test notification message #{n}" }
  end
end
