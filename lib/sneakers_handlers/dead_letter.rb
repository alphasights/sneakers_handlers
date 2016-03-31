module SneakersHandlers
  class DeadLetter < ::Sneakers::Handlers::Oneshot
    def initialize(channel, queue, options)
      super

      create_dead_letter_exchange!(channel, queue, options)
    end

    private

    def create_dead_letter_exchange!(channel, queue, options)
      arguments = options[:queue_options][:arguments]

      dlx = channel.exchange(arguments.fetch("x-dead-letter-exchange"), {
        type: options[:exchange_options][:type],
        durable: options[:exchange_options][:durable],
      })

      dlx_queue = channel.queue("#{queue.name}.dlx", durable: options[:queue_options][:durable])
      dlx_queue.bind(dlx, routing_key: arguments.fetch("x-dead-letter-routing-key"))
    end
  end
end
