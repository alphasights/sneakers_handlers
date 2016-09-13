require "test_helper"
require "support/retry_worker_failure"
require "support/retry_worker_success"

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

    success_dead_letter_queue = channel.queue(RetryWorkerSuccess.queue_name + ".dlx")
    failure_dead_letter_queue = channel.queue(RetryWorkerFailure.queue_name + ".dlx")

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
      channel.queue_delete(worker.queue_name + ".dlx")
    end
  end
end
