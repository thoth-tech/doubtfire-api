require 'faker'

FactoryBot.define do
  factory :notification do
    user
    notification_type { 'general' }
    event { "#{notification_type}_event" }
    message { Faker::Lorem.sentence }
    link { nil }
    read_at { nil }

    trait :task do
      notification_type { 'task' }
    end

    trait :feedback do
      notification_type { 'feedback' }
    end

    trait :portfolio do
      notification_type { 'portfolio' }
    end

    trait :extension do
      notification_type { 'extension' }
    end

    trait :general do
      notification_type { 'general' }
    end

    trait :read do
      read_at { Time.zone.now }
    end

    trait :unread do
      read_at { nil }
    end
  end
end
