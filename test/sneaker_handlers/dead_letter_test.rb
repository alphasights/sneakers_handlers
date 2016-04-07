require "test_helper"

class SneakersHandlers::DeadLetterTest < Minitest::Test
  extend MiniTest::Spec::DSL
  let(:channel) { Minitest::Mock.new() }
  let(:queue) {
    q = Minitest::Mock.new
    q.expect :name, "test.queue"
    q
  }
  let(:dlx_queue) { Minitest::Mock.new() }
  let(:dlx_exchange) { Minitest::Mock.new() }
  let(:options) do
    {
      routing_key: "pistachio.test",
      exchange_options: {
        type: :fanout,
        durable: true
      },
      queue_options: {
        durable: true,
        arguments: {
          "x-dead-letter-exchange" => "test.dlx",
          "x-dead-letter-routing-key" => "dlx-routing-key"
        }
      }
    }
  end

  def test_create_dead_letter_exchange_and_queue
    channel.expect :exchange, dlx_exchange, ['test.dlx', {
       type: :fanout,
       durable: true,
     }]

    channel.expect :queue, dlx_queue, ["test.queue.dlx", {
      durable: true
    }]

    dlx_queue.expect(:bind, nil,[dlx_exchange, routing_key: "dlx-routing-key"])

    SneakersHandlers::DeadLetter.new(channel, queue, options)
  end

  def test_raises_key_error_if_xdeadletterexchange_argument_not_set
    options[:queue_options][:arguments].delete("x-dead-letter-exchange")
    assert_raises KeyError do
      SneakersHandlers::DeadLetter.new(channel, queue, options)
    end
  end
end
