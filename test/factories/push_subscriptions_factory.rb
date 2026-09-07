FactoryBot.define do
  factory :push_subscription do
    user

    # The endpoint is unique across the whole table, not per user, so the
    # sequence alone is not enough. A test that leaks a row past its transaction
    # would leave that endpoint in the database for the next run and the
    # collision would look like a bug in whatever test built it second.
    sequence(:endpoint) { |n| "https://fcm.googleapis.com/fcm/send/factory-#{n}-#{SecureRandom.hex(8)}" }

    # A throwaway browser key pair. The p256dh has to be a real prime256v1
    # public key because PushNotificationService encrypts against it through the
    # web-push gem, and the gem cannot encrypt to a made up string. The auth
    # secret has to decode to 16 bytes for the same reason.
    p256dh { 'BJy8RpjMkwOPDIIXSu-FTe7OosAwY9G86_evhrn0jJbPnoxXjBYpn7aPHEIaRh3GxCzFvwYXjKWvtu3FEMaBQMY=' }
    auth   { 'CUkmaYqq8eINt1HTnFY65w==' }
  end
end
