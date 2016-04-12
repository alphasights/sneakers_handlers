$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'dotenv'
Dotenv.load
require 'sneakers_handlers'

require 'minitest/autorun'

require "sneakers"

Sneakers.configure({
  amqp: ENV["RABBITMQ_URL"],
  vhost: ENV["RABBITMQ_VHOST"],
  heartbeat: 10,
  prefetch: Integer(ENV["RABBITMQ_PREFETCH"] || 5),
  workers: Integer(ENV["RABBITMQ_WORKERS"] || 1),
  threads: Integer(ENV["RABBITMQ_THREADS"] || 5)
})

Sneakers.logger.level = Integer(ENV["SNEAKERS_LOG_LEVEL"] || Logger::INFO)
