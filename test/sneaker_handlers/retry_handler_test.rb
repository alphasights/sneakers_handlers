require "test_helper"
require "sneakers"
require "sneakers/runner"
require "rabbitmq/http/client"
require 'pry'

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
      puts "WORKING: #{x}\n"

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

    sleep 10

    dead_letter = channel.queue(TestWorker.queue_name + ".dlx")
    assert_equal 0, dead_letter.message_count
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
