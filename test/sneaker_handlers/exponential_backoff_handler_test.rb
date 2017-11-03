require_relative "../test_helper"
require_relative "../../lib/sneakers_handlers/exponential_backoff_handler"

class SneakersHandlers::ExponentialBackoffHandlerTest < Minitest::Test
  class FailingWorker
    include Sneakers::Worker

    from_queue "sneaker_handlers.exponential_back_test",
      ack: true,
      durable: false,
      max_retries: 2,
      exchange: "sneakers_handlers",
      exchange_type: :topic,
      routing_key: "lifecycle.created",
      handler: SneakersHandlers::ExponentialBackoffHandler,
      arguments: {
        "x-dead-letter-exchange" => "sneakers_handlers.error",
        "x-dead-letter-routing-key" => "sneakers_handlers.exponential_back_test"
      }

    def work(payload)
      if payload == "unhandled_exception"
        raise "Unhandled exceptions should be retried"
      end

      return payload.to_sym
    end
  end

  def setup
    cleanup!
  end

  def teardown
    cleanup!
  end

  def test_handler_retries_with_ttl_retry_queues
    exchange = channel.topic("sneakers_handlers", durable: false)

    ["timeout", "error", "requeue", "reject", "unhandled_exception"].each do |type_of_failure|
      FailingWorker.new.run
      exchange.publish(type_of_failure, routing_key: "lifecycle.created")
      sleep 0.1
    end

    assert_equal 5, retry_queue(1).message_count
    assert_equal 0, retry_queue(4).message_count
    assert_equal 0, error_queue.message_count

    sleep 1

    assert_equal 0, retry_queue(1).message_count
    assert_equal 5, retry_queue(4).message_count
    assert_equal 0, error_queue.message_count

    sleep 4

    assert_equal 0, retry_queue(4).message_count
    assert_equal 5, error_queue.message_count

    ["timeout", "error", "requeue", "reject", "unhandled_exception"].each do |type_of_failure|
      FailingWorker.new.run
      exchange.publish(type_of_failure, routing_key: "lifecycle.created")
      sleep 0.1
    end

    assert_equal 5, retry_queue(1).message_count
    assert_equal 0, retry_queue(4).message_count

    sleep 1

    assert_equal 0, retry_queue(1).message_count
    assert_equal 5, retry_queue(4).message_count

    sleep 4

    assert_equal 10, error_queue.message_count

    rejection_reasons = error_queue.message_count.times.map do
      _delivery_info, properties, _message = channel.basic_get(error_queue.name, manual_ack: false)
      properties.dig(:headers, "rejection_reason")
    end.uniq

    expected_reasons = ["timeout", "nil", "reject", "#<RuntimeError: Unhandled exceptions should be retried>"]
    assert_equal expected_reasons.sort, rejection_reasons.sort
  end

  def test_works_when_shoveling_messages
    exchange = channel.default_exchange

    ["timeout", "error", "requeue", "reject"].each do |type_of_failure|
      FailingWorker.new.run
      exchange.publish(type_of_failure, routing_key: "sneaker_handlers.exponential_back_test")
      sleep 0.1
    end

    assert_equal 4, retry_queue(1).message_count
    assert_equal 0, retry_queue(4).message_count
    assert_equal 0, error_queue.message_count

    sleep 1

    assert_equal 0, retry_queue(1).message_count
    assert_equal 4, retry_queue(4).message_count
    assert_equal 0, error_queue.message_count

    sleep 4

    assert_equal 0, retry_queue(4).message_count
    assert_equal 4, error_queue.message_count
  end

  def test_custom_backoff_function
    exchange = channel.default_exchange

    Class.new do
      include Sneakers::Worker

      from_queue "sneaker_handlers.exponential_back_test",
        ack: true,
        durable: false,
        max_retries: 2,
        exchange: "sneakers_handlers",
        exchange_type: :topic,
        routing_key: ["lifecycle.created", "lifecycle.updated"],
        handler: SneakersHandlers::ExponentialBackoffHandler,
        backoff_function: ->(attempt_number) { attempt_number + 1 },
        arguments: {
          "x-dead-letter-exchange" => "sneakers_handlers.error",
          "x-dead-letter-routing-key" => "sneakers_handlers.exponential_back_test"
        }

        def work(payload)
          return payload.to_sym
        end
    end.new.run

    exchange.publish("error", routing_key: "sneaker_handlers.exponential_back_test")
    sleep 0.1

    assert_equal 1, retry_queue(1).message_count
    assert_equal 0, retry_queue(2).message_count
    assert_equal 0, error_queue.message_count

    sleep 1

    assert_equal 0, retry_queue(1).message_count
    assert_equal 1, retry_queue(2).message_count
    assert_equal 0, error_queue.message_count

    sleep 2

    assert_equal 0, retry_queue(2).message_count
    assert_equal 1, error_queue.message_count
  end

  def test_respects_primary_exchange_type
    exchange = channel.default_exchange

    Class.new do
      include Sneakers::Worker

      from_queue "sneaker_handlers.exponential_back_test",
        ack: true,
        durable: false,
        max_retries: 2,
        exchange: "sneakers_handlers",
        exchange_type: :direct,
        routing_key: ["lifecycle.created", "lifecycle.updated"],
        handler: SneakersHandlers::ExponentialBackoffHandler,
        arguments: {
          "x-dead-letter-exchange" => "sneakers_handlers.error",
          "x-dead-letter-routing-key" => "sneakers_handlers.exponential_back_test"
        }

        def work(payload)
          return :reject
        end
    end.new.run

    exchange.publish("", routing_key: "sneaker_handlers.exponential_back_test")
    sleep 0.1

    assert_equal 1, retry_queue(1).message_count
  end

  def test_removes_x_delay_header
    exchange = channel.topic("sneakers_handlers", durable: false)

    FailingWorker.new.run
    exchange.publish("error", routing_key: "lifecycle.created", headers: { "x-delay" => 1 })
    sleep 0.1

    assert_equal 1, retry_queue(1).message_count
    _, args, _ = retry_queue(1).pop
    assert args[:headers].is_a?(Hash)
    refute args[:headers].has_key?("x-delay"), "Should remove the x-delay header"
  end

  private

  def retry_queue(count)
    channel.queue("sneaker_handlers.exponential_back_test.retry.#{count}",
      durable: false,
      arguments: {
        :"x-dead-letter-exchange" => "sneakers_handlers",
        :"x-dead-letter-routing-key" => "sneaker_handlers.exponential_back_test",
        :"x-message-ttl" => count * 1_000,
        :"x-expires" => count * 1_000 * 2,
      }
    )
  end

  def error_queue
    channel.queue("sneaker_handlers.exponential_back_test.error")
  end

  def channel
    @channel ||= begin
                   connection = Bunny.new.start
                   connection.create_channel
                 end
  end

  def cleanup!
    channel.exchange_delete("sneakers_handlers")
    channel.exchange_delete("sneakers_handlers.retry")
    channel.exchange_delete("sneakers_handlers.error")

    [FailingWorker].each do |worker|
      channel.queue_delete(worker.queue_name)
      channel.queue_delete(worker.queue_name + ".error")
      channel.queue_delete(worker.queue_name + ".retry.1")
      channel.queue_delete(worker.queue_name + ".retry.4")
    end
  end
end
