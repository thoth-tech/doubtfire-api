# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../app/services/readiness_check'

class ReadinessCheckUnitTest < Minitest::Test
  class DatabaseConnection
    attr_reader :queries

    def initialize(result: 1, error: nil)
      @result = result
      @error = error
      @queries = []
    end

    def select_value(query)
      @queries << query
      raise @error if @error

      @result
    end
  end

  class DatabaseConnectionPool
    def initialize(connection)
      @connection = connection
    end

    def with_connection
      yield @connection
    end
  end

  class RedisConnection
    def initialize(result: 'PONG', error: nil)
      @result = result
      @error = error
    end

    def ping
      raise @error if @error

      @result
    end
  end

  class RedisGateway
    def initialize(connection)
      @connection = connection
    end

    def redis
      yield @connection
    end
  end

  def test_ready_when_database_and_redis_respond
    connection = DatabaseConnection.new
    check = build_check(database: connection)

    assert check.ready?
    assert_equal ['SELECT 1'], connection.queries
  end

  def test_not_ready_when_database_returns_an_unexpected_result
    assert_equal false, build_check(database: DatabaseConnection.new(result: 0)).ready?
  end

  def test_not_ready_when_database_raises
    database = DatabaseConnection.new(error: RuntimeError.new('database details'))

    assert_equal false, build_check(database: database).ready?
  end

  def test_not_ready_when_redis_returns_an_unexpected_result
    redis = RedisConnection.new(result: 'NOT PONG')

    assert_equal false, build_check(redis: redis).ready?
  end

  def test_not_ready_when_redis_raises
    redis = RedisConnection.new(error: RuntimeError.new('redis details'))

    assert_equal false, build_check(redis: redis).ready?
  end

  private

  def build_check(database: DatabaseConnection.new, redis: RedisConnection.new)
    ReadinessCheck.new(
      database_connection_pool: DatabaseConnectionPool.new(database),
      redis: RedisGateway.new(redis)
    )
  end
end
