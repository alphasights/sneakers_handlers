require_relative "../test_helper"
require_relative "../../lib/sneakers_handlers/exponential_backoff_handler"

class SneakersHandlers::ExponentialBackoffHandlerTest < Minitest::Test
  class FailingWorker
    include Sneakers::Worker

    from_queue "sneaker_handlers.exponential_back_test",
      ack: true,
      durable: false,
      delays: [1, 3, 5],
      exchange: "sneakers_handlers",
      exchange_type: :topic,
      routing_key: "lifecycle.created",
      handler: SneakersHandlers::ExponentialBackoffHandler,
      arguments: {
        "x-dead-letter-exchange" => "sneakers_handlers.error"
      }

    def work(payload)
      return reject!
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
    worker = FailingWorker.new

    worker.run
    exchange.publish("{}", routing_key: "lifecycle.created")

    sleep 0.1

    assert_equal 1, retry_queue(1).message_count
    assert_equal 0, retry_queue(3).message_count
    assert_equal 0, retry_queue(5).message_count
    assert_equal 0, error_queue.message_count

    sleep 1

    assert_equal 0, retry_queue(1).message_count
    assert_equal 1, retry_queue(3).message_count
    assert_equal 0, retry_queue(5).message_count
    assert_equal 0, error_queue.message_count

    sleep 3

    assert_equal 0, retry_queue(3).message_count
    assert_equal 1, retry_queue(5).message_count
    assert_equal 0, error_queue.message_count

    sleep 5

    assert_equal 0, retry_queue(3).message_count
    assert_equal 0, retry_queue(5).message_count
    assert_equal 1, error_queue.message_count
  end

  private

  def retry_queue(count)
    channel.queue("sneaker_handlers.exponential_back_test.retry.#{count}",
      durable: false,
      arguments: {
        :"x-dead-letter-exchange" => "sneakers_handlers",
        :"x-message-ttl" => count * 1_000,
        :"x-expires" => count * 2_000,
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
      channel.queue_delete(worker.queue_name + ".retry.3")
      channel.queue_delete(worker.queue_name + ".retry.5")
    end
  end
end
