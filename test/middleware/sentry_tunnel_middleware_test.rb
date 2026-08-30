# frozen_string_literal: true

require 'active_support/core_ext/object/blank'
require 'minitest/autorun'
require 'stringio'
require 'webmock/minitest'
require_relative '../../app/middleware/sentry_tunnel_middleware'

class SentryTunnelMiddlewareTest < Minitest::Test
  ENVELOPE_URL = 'https://sentry.example/api/123/envelope/?sentry_key=public'

  def setup
    @original_dsn = ENV.fetch('SENTRY_DSN', nil)
    ENV['SENTRY_DSN'] = 'https://public@sentry.example/123'
    @middleware = SentryTunnelMiddleware.new(->(_env) { [404, {}, []] })
  end

  def teardown
    @original_dsn.nil? ? ENV.delete('SENTRY_DSN') : ENV['SENTRY_DSN'] = @original_dsn
    super
  end

  def test_envelope_at_limit_is_forwarded
    body = 'a' * SentryTunnelMiddleware::MAX_ENVELOPE_BYTES
    request = stub_request(:post, ENVELOPE_URL).with(body: body).to_return(status: 200)
    env = request_environment(body, content_length: body.bytesize)

    assert_equal [204, {}, []], @middleware.call(env)
    assert_requested request, times: 1
    assert_equal 0, env.fetch('rack.input').pos
  end

  def test_envelope_over_limit_without_declared_length_is_rejected
    assert_oversized_envelope_rejected(content_length: nil)
  end

  def test_envelope_over_limit_with_lying_small_length_is_rejected
    assert_oversized_envelope_rejected(content_length: 1)
  end

  def test_declared_oversized_envelope_is_rejected_before_reading
    request = stub_request(:post, ENVELOPE_URL)
    env = request_environment('small', content_length: SentryTunnelMiddleware::MAX_ENVELOPE_BYTES + 1)

    assert_equal [413, { 'content-length' => '0' }, []], @middleware.call(env)
    assert_not_requested request
    assert_equal 0, env.fetch('rack.input').pos
  end

  private

  def assert_oversized_envelope_rejected(content_length:)
    body = 'a' * (SentryTunnelMiddleware::MAX_ENVELOPE_BYTES + 1)
    request = stub_request(:post, ENVELOPE_URL)
    env = request_environment(body, content_length: content_length)

    assert_equal [413, { 'content-length' => '0' }, []], @middleware.call(env)
    assert_not_requested request
    assert_equal 0, env.fetch('rack.input').pos
  end

  def request_environment(body, content_length:)
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => SentryTunnelMiddleware::PATH,
      'CONTENT_TYPE' => 'application/x-sentry-envelope',
      'rack.input' => StringIO.new(body)
    }
    env['CONTENT_LENGTH'] = content_length.to_s unless content_length.nil?
    env
  end
end
