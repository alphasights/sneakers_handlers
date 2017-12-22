require "test_helper"

class SneakersHandlers::DeadLetterHandlerTest < Minitest::Test
  def setup
    cleanup!
  end

  def teardown
    cleanup!
  end

  def test_dead_letter_messages
    exchange = channel.topic("sneakers_handlers", durable: false)

    DeadLetterWorkerFailure.new.run
    DeadLetterWorkerSuccess.new.run

    2.times do
      exchange.publish("test message", routing_key: "sneakers_handlers.dead_letter_test")
    end

    sleep 0.1

    success_dead_letter_queue = channel.queue(DeadLetterWorkerSuccess.queue_name + ".error")
    failure_dead_letter_queue = channel.queue(DeadLetterWorkerFailure.queue_name + ".error")

    assert_equal 2, failure_dead_letter_queue.message_count
    assert_equal 0, success_dead_letter_queue.message_count
  end

  def test_works_with_fanout_exchange
    exchange = channel.fanout("sneakers_handlers", durable: false)

    DeadLetterFanoutWorkerFailure.new.run
    DeadLetterFanoutWorkerSuccess.new.run

    2.times do
      exchange.publish("test message")
    end

    sleep 0.1

    success_dead_letter_queue = channel.queue(DeadLetterFanoutWorkerSuccess.queue_name + ".error")
    failure_dead_letter_queue = channel.queue(DeadLetterFanoutWorkerFailure.queue_name + ".error")

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

  def cleanup!
    channel.exchange_delete("sneakers_handlers")
    channel.exchange_delete("sneakers_handlers.dlx")

    [DeadLetterWorkerFailure, DeadLetterWorkerSuccess].each do |worker|
      channel.queue_delete(worker.queue_name)
      channel.queue_delete(worker.queue_name + ".error")
    end
  end
end

class DeadLetterWorkerSuccess
  include Sneakers::Worker

  from_queue "sneakers_handlers.dead_letter_success_test",
    ack: true,
    durable: false,
    exchange: "sneakers_handlers",
    exchange_type: :topic,
    routing_key: "sneakers_handlers.dead_letter_test",
    handler: SneakersHandlers::DeadLetterHandler,
    arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                 "x-dead-letter-routing-key" => "sneakers_handlers.dead_letter_success_test" }

  def work(*args)
    ack!
  end
end

class DeadLetterWorkerFailure
  include Sneakers::Worker

  from_queue "sneakers_handlers.dead_letter_failure_test",
    ack: true,
    durable: false,
    exchange: "sneakers_handlers",
    exchange_type: :topic,
    routing_key: "sneakers_handlers.dead_letter_test",
    handler: SneakersHandlers::DeadLetterHandler,
    arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                 "x-dead-letter-routing-key" => "sneakers_handlers.dead_letter_failure_test" }

  def work(*args)
    reject!
  end
end

class DeadLetterFanoutWorkerSuccess
  include Sneakers::Worker

  from_queue "sneakers_handlers.dead_letter_success_test",
    ack: true,
    durable: false,
    exchange: "sneakers_handlers",
    exchange_type: :fanout,
    routing_key: "sneakers_handlers.dead_letter_test",
    handler: SneakersHandlers::DeadLetterHandler,
    arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                 "x-dead-letter-routing-key" => "sneakers_handlers.dead_letter_success_test" }

  def work(*args)
    ack!
  end
end

class DeadLetterFanoutWorkerFailure
  include Sneakers::Worker

  from_queue "sneakers_handlers.dead_letter_failure_test",
    ack: true,
    durable: false,
    exchange: "sneakers_handlers",
    exchange_type: :fanout,
    routing_key: "sneakers_handlers.dead_letter_test",
    handler: SneakersHandlers::DeadLetterHandler,
    arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                 "x-dead-letter-routing-key" => "sneakers_handlers.dead_letter_failure_test" }

  def work(*args)
    reject!
  end
end
