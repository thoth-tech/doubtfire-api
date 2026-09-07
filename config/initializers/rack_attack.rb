require 'digest'
require 'json'

# Rack::Attack 6.8 uses Rack::Request, whose params do not parse JSON request
# bodies. Use Rails' parser, which rewinds and caches rack.input for the app.
module Rack
  class Attack
    class Request
      AUTH_PATH = %r{\A/api/auth(?:\.json)?\z}

      def password_authentication_request?
        post? && path.match?(AUTH_PATH)
      end

      def authentication_username_digest
        username =
          if media_type == 'application/json'
            ActionDispatch::Request.new(env).request_parameters['username']
          else
            params['username']
          end
        return unless username.is_a?(String)

        normalized_username = username.downcase.strip
        Digest::SHA256.hexdigest(normalized_username) if normalized_username.present?
      rescue ActionDispatch::Http::Parameters::ParseError
        nil
      end
    end
  end
end

# Prefer the application's dedicated Redis cache and fall back to the mandatory
# Sidekiq Redis service. Process-local stores do not enforce a deployment-wide
# throttle when the API is replicated.
shared_redis_url =
  ENV.fetch('DF_REDIS_CACHE_URL', nil).presence ||
  ENV.fetch('DF_REDIS_SIDEKIQ_URL', nil).presence

Rack::Attack.cache.store =
  if shared_redis_url.present? && !Rails.env.test?
    ActiveSupport::Cache::RedisCacheStore.new(
      url: shared_redis_url,
      namespace: 'doubtfire:rack-attack'
    )
  elsif Rails.env.local?
    Rails.cache
  else
    raise 'Set DF_REDIS_CACHE_URL or DF_REDIS_SIDEKIQ_URL to enable authentication rate limiting'
  end

Rack::Attack.throttled_response_retry_after_header = true
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env.fetch('rack.attack.match_data')
  retry_after = match_data[:period] - (match_data[:epoch_time] % match_data[:period])

  [
    429,
    {
      'content-type' => 'application/json',
      'retry-after' => retry_after.to_s
    },
    [JSON.generate(error: 'Too many authentication attempts. Please try again later.')]
  ]
end

# Limit authentication attempts from a single IP.
Rack::Attack.throttle('auth/ip', limit: 5, period: 1.minute) do |req|
  req.ip if req.password_authentication_request?
end

# Limit attempts against a single username without storing that username in the
# rate-limit cache key.
Rack::Attack.throttle('auth/username', limit: 5, period: 1.minute) do |req|
  req.authentication_username_digest if req.password_authentication_request?
end
