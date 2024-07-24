# frozen_string_literal: true

Sidekiq.class_eval do
  def self.redis=(hash)
    Rails.logger.warn("Sidekiq.redis=-------------------------")
    Rails.logger.warn(hash)
    @redis = if hash.is_a?(ConnectionPool)
               hash
             else
               Sidekiq::RedisConnection.create(hash)
             end
    Rails.logger.warn("Sidekiq.redis=-------------------------EOL")
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    network_timeout: ENV.fetch("REDIS_NETWORK_TIMEOUT", 10),
    pool_timeout: ENV.fetch("REDIS_POOL_TIMEOUT", 10),
    reconnect_attempts: ENV.fetch("REDIS_RECONNECT_ATTEMPTS", 1)
  }
end
