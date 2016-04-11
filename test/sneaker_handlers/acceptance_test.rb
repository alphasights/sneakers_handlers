require 'pry-byebug'
require "test_helper"
require "sneakers"
require "sneakers/runner"
require "rabbitmq/http/client"

require_relative "workers/dead_letter_worker_failure"
require_relative "workers/dead_letter_worker_success"

class SneakersHandlers::AcceptanceTest < Minitest::Test

  def test_dead_letter_messages
    delete_test_queues!
    configure_sneakers

    exchange = channel.topic("sneakers_handlers", durable: false)

    DeadLetterWorkerFailure.new.run
    DeadLetterWorkerSuccess.new.run

    2.times do
      exchange.publish("test message", routing_key: "sneakers_handlers.dead_letter_test")
    end

    sleep 0.1
    success_dead_letter_queue = channel.queue(DeadLetterWorkerSuccess.queue_name + ".dlx")
    failure_dead_letter_queue = channel.queue(DeadLetterWorkerFailure.queue_name + ".dlx")

    assert_equal 2, failure_dead_letter_queue.message_count
    assert_equal 0, success_dead_letter_queue.message_count
  end

  private

  def channel
    @channel ||= begin
                   connection = Bunny.new.start
                   connection.create_channel
                 end
  end

  def delete_test_queues!
    admin = RabbitMQ::HTTP::Client.new("http://127.0.0.1:15672/", username: "guest", password: "guest")
    queues = admin.list_queues
    queues.each do |q|
      name = q.name
      admin.delete_queue('/', name) if name.start_with?("sneaker_handlers")
    end
  end

  def configure_sneakers
    Sneakers.configure
    Sneakers.logger.level = Logger::ERROR
  end
end
