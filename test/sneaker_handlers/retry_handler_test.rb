require "test_helper"
require "sneakers"
require "sneakers/runner"
require "rabbitmq/http/client"
require 'pry'
require 'json'

class SneakersHandlers::AcceptanceTest < Minitest::Test

  class TestWorker
    include Sneakers::Worker

    from_queue "sneaker_handlers.dead_letter_success_test",
    ack: true,
    durable: false,
    exchange: "sneakers_handlers",
    exchange_type: :topic,
    routing_key: "sneakers_handlers.dead_letter_test",
    handler: SneakersHandlers::RetryHandler,
    arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                 "x-dead-letter-routing-key" => "sneaker_handlers.dead_letter_success_test" }

    def work(payload)
      JSON.parse(payload)
      response = payload["response"]
      x = JSON.parse(payload)["response"] + "!"
      return reject!
    end
  end

  def test_dead_letter_messages
    delete_test_queues!
    configure_sneakers

    exchange = channel.topic("sneakers_handlers", durable: false)

    worker = TestWorker.new
    worker.run

    json = <<-JSON
      {
        "response":"reject"
      }
    JSON

    1.times do
      exchange.publish(json, routing_key: "sneakers_handlers.dead_letter_test")
    end

    sleep 5

    dead_letter = channel.queue(TestWorker.queue_name + ".dlx")
    assert_equal 1, dead_letter.message_count
  end

  private

  def channel
    @channel ||= begin
                   connection = Bunny.new.start
                   connection.create_channel
                 end
  end

  def delete_test_queues!
    channel.queue_delete(TestWorker.queue_name)
    channel.queue_delete("#{TestWorker.queue_name}.dlx")
  end

  def configure_sneakers
    Sneakers.configure
    Sneakers.logger.level = Logger::ERROR
  end
end
