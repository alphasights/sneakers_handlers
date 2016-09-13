require "test_helper"
require "support/dead_letter_worker_failure"
require "support/dead_letter_worker_success"

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

  def cleanup!
    channel.exchange_delete("sneakers_handlers")
    channel.exchange_delete("sneakers_handlers.dlx")

    [DeadLetterWorkerFailure, DeadLetterWorkerSuccess].each do |worker|
      channel.queue_delete(worker.queue_name)
      channel.queue_delete(worker.queue_name + ".dlx")
    end
  end
end
