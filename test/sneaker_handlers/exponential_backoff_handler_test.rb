require "test_helper"
require "sneakers_handlers/exponential_backoff_handler"

class SneakersHandlers::ExponentialBackoffHandlerTest < Minitest::Test
  class RetryWorkerFailure
    include Sneakers::Worker

    from_queue "sneaker_handlers.exponential_back_test",
      ack: true,
      durable: false,
      delays: [1, 5, 10],
      exchange: "sneakers_handlers",
      exchange_type: :topic,
      routing_key: "lifecycle.created",
      handler: SneakersHandlers::ExponentialBackoffHandler

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

  def test_max_retry_goes_to_dlx
    exchange = channel.topic("sneakers_handlers", durable: false)

    RetryWorkerFailure.new.run

    # exchange.publish("{}", routing_key: "lifecycle.created")
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
    channel.exchange_delete("sneakers_handlers.retry")
    channel.exchange_delete("sneakers_handlers.error")

    [RetryWorkerFailure].each do |worker|
      channel.queue_delete(worker.queue_name)
      channel.queue_delete(worker.queue_name + ".error")
      channel.queue_delete(worker.queue_name + ".retry")
      channel.queue_delete(worker.queue_name + ".retry.1")
      channel.queue_delete(worker.queue_name + ".retry.10")
      channel.queue_delete(worker.queue_name + ".retry.100")
      channel.queue_delete(worker.queue_name + ".retry.1000")
    end
  end
end
