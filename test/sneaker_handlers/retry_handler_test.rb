require "test_helper"
require "sneakers"
require "support/test_worker"

class SneakersHandlers::AcceptanceTest < Minitest::Test
  def test_max_retry_goes_to_dlx
    delete_test_queues!
    configure_sneakers

    exchange = channel.topic("sneakers_handlers", durable: false)

    worker = TestWorker.new
    worker.run

    exchange.publish("{}", routing_key: "sneakers_handlers.dead_letter_test")

    sleep 5 #wait for the worker to deal with messages

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
