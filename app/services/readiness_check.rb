class ReadinessCheck
  DATABASE_QUERY = 'SELECT 1'.freeze

  def initialize(database_connection_pool: ActiveRecord::Base.connection_pool, redis: Sidekiq)
    @database_connection_pool = database_connection_pool
    @redis = redis
  end

  def ready?
    database_ready? && redis_ready?
  rescue StandardError
    false
  end

  private

  def database_ready?
    result = @database_connection_pool.with_connection do |connection|
      connection.select_value(DATABASE_QUERY)
    end

    result.to_s == '1'
  end

  def redis_ready?
    @redis.redis(&:ping) == 'PONG'
  end
end
