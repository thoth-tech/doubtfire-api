require 'test_helper'
require 'minitest/mock'

class ReadinessControllerTest < ActionDispatch::IntegrationTest
  StaticReadinessCheck = Struct.new(:result) do
    def ready?
      result
    end
  end

  test 'returns ok without authentication when dependencies are ready' do
    ReadinessCheck.stub(:new, StaticReadinessCheck.new(true)) do
      get '/readiness'
    end

    assert_response :ok
    assert_empty response.body
  end

  test 'returns only service unavailable when a dependency is down' do
    ReadinessCheck.stub(:new, StaticReadinessCheck.new(false)) do
      get '/readiness'
    end

    assert_response :service_unavailable
    assert_empty response.body
  end
end
