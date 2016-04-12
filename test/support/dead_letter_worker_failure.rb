require 'sneakers'

class DeadLetterWorkerSuccess
  include Sneakers::Worker

  from_queue "sneaker_handlers.dead_letter_success_test",
    ack: true,
    durable: false,
    exchange: "sneakers_handlers",
    exchange_type: :topic,
    routing_key: "sneakers_handlers.dead_letter_test",
    handler: SneakersHandlers::DeadLetterHandler,
    arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                 "x-dead-letter-routing-key" => "sneaker_handlers.dead_letter_success_test" }

  def work(*args)
    ack!
  end
end
