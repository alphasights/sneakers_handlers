require "test_helper"

class SneakersHandlers::RetryHandlerTest < Minitest::Test
  def setup
    cleanup!
  end

  def teardown
    cleanup!
  end

  def test_max_retry_goes_to_dlx
    exchange = channel.topic("sneakers_handlers", durable: false)

    RetryWorkerFailure.new.run
    RetryWorkerSuccess.new.run

    2.times do
      exchange.publish("{}", routing_key: "sneakers_handlers.retry_test")
    end

    sleep 0.1 # wait for the worker to deal with messages

    success_dead_letter_queue = channel.queue(RetryWorkerSuccess.queue_name + ".error")
    failure_dead_letter_queue = channel.queue(RetryWorkerFailure.queue_name + ".error")

    assert_equal 2, failure_dead_letter_queue.message_count
    assert_equal 0, success_dead_letter_queue.message_count
  end

  def test_works_with_fanout_exchange
    exchange = channel.fanout("sneakers_handlers", durable: false)

    RetryFanoutWorkerFailure.new.run
    RetryFanoutWorkerSuccess.new.run

    2.times do
      exchange.publish("{}")
    end

    sleep 0.1 # wait for the worker to deal with messages

    success_dead_letter_queue = channel.queue(RetryFanoutWorkerSuccess.queue_name + ".error")
    failure_dead_letter_queue = channel.queue(RetryFanoutWorkerFailure.queue_name + ".error")

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

    [RetryWorkerFailure, RetryWorkerSuccess].each do |worker|
      channel.queue_delete(worker.queue_name)
      channel.queue_delete(worker.queue_name + ".error")
    end
  end
end

class RetryWorkerSuccess
  include Sneakers::Worker

  from_queue "sneaker_handlers.retry_success_test",
  ack: true,
  durable: false,
  exchange: "sneakers_handlers",
  exchange_type: :topic,
  routing_key: "sneakers_handlers.retry_test",
  handler: SneakersHandlers::RetryHandler,
  arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
               "x-dead-letter-routing-key" => "sneaker_handlers.retry_success_test" }

  def work(payload)
    return ack!
  end
end

class RetryWorkerFailure
  include Sneakers::Worker

  from_queue "sneaker_handlers.retry_failure_test",
  ack: true,
  durable: false,
  exchange: "sneakers_handlers",
  exchange_type: :topic,
  routing_key: "sneakers_handlers.retry_test",
  handler: SneakersHandlers::RetryHandler,
  arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
               "x-dead-letter-routing-key" => "sneaker_handlers.retry_failure_test" }

  def work(payload)
    return reject!
  end
end

class RetryFanoutWorkerSuccess
  include Sneakers::Worker

  from_queue "sneaker_handlers.retry_success_test",
  ack: true,
  durable: false,
  exchange: "sneakers_handlers",
  exchange_type: :fanout,
  routing_key: "sneakers_handlers.retry_test",
  handler: SneakersHandlers::RetryHandler,
  arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
               "x-dead-letter-routing-key" => "sneaker_handlers.retry_success_test" }

  def work(payload)
    return ack!
  end
end

class RetryFanoutWorkerFailure
  include Sneakers::Worker

  from_queue "sneaker_handlers.retry_failure_test",
  ack: true,
  durable: false,
  exchange: "sneakers_handlers",
  exchange_type: :fanout,
  routing_key: "sneakers_handlers.retry_test",
  handler: SneakersHandlers::RetryHandler,
  arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
               "x-dead-letter-routing-key" => "sneaker_handlers.retry_failure_test" }

  def work(payload)
    return reject!
  end
end
