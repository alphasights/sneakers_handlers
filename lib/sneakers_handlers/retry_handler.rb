# Using this handler, failed messages will be retried a certain number of times,
# until they are dead-lettered.
#
# To use it you need to defined this handler in your worker:
#
# from_queue "my-app.queue_name",
#   exchange: "domain_events",
#   routing_key: "my_routing_key",
#   handler: Sneakers::Handlers::RetryHandler,
#   arguments: { "x-dead-letter-exchange" => "dlx.domain_events",
#                "x-dead-letter-routing-key" => "my-app.queue_name" }}
#
# By default it will retry 5 times before dead-lettering a message, but you can
# also customize that with the `max_retry` option:
#
# from_queue "my-app.queue_name",
#   exchange: "domain_events",
#   routing_key: "my_routing_key",
#   handler: Sneakers::Handlers::RetryHandler,
#   max_retry: 10,
#   arguments: { "x-dead-letter-exchange" => "dlx.domain_events" }
#                "x-dead-letter-routing-key" => "my-app.queue_name" }}

module SneakersHandlers
  class RetryHandler

    def initialize(channel, queue, options)
      @channel = channel
      @queue = queue
      @routing_key = options[:routing_key]
      @max_retry = options.fetch(:max_retry, 5)

      create_dlx(channel, queue, options)
    end

    def acknowledge(hdr, _props, _msg)
      @channel.acknowledge(hdr.delivery_tag, false)
    end

    def reject(hdr, props, msg, requeue = false)
      if requeue
        @channel.reject(hdr.delivery_tag, requeue)
      else
        retry_message(hdr, props, msg)
      end
    end

    def error(hdr, props, msg, _err)
      retry_message(hdr, props, msg)
    end

    def timeout(hdr, props, msg)
      retry_message(hdr, props, msg)
    end

    def noop(_hdr, _props, _msg)
    end

    private

    def create_dlx(channel, queue, options)
      arguments = options[:queue_options][:arguments]

      dlx_exchange_name = arguments.fetch("x-dead-letter-exchange")
      dlx_exchange = channel.exchange(dlx_exchange_name, {
        type: options[:exchange_options][:type],
        durable: options[:exchange_options][:durable],
      })

      @dlx_queue = channel.queue("#{queue.name}.dlx", durable: options[:queue_options][:durable])
      @dlx_queue.bind(dlx_exchange, routing_key: arguments.fetch("x-dead-letter-routing-key"))
    end

    def retry_message(hdr, props, msg)
      headers = props[:headers] || {}

      retry_count = headers.fetch("x-retry-count", 1)
      if retry_count >= @max_retry
        @channel.default_exchange.publish(msg, routing_key: @dlx_queue.name)
      else
        Sneakers.logger.info do
          "Retrying message: queue=#{@queue.name} retry_count=#{retry_count}."
        end

        @channel.default_exchange.publish(msg,
                                          routing_key: @queue.name,
                                          headers: { "x-retry-count": retry_count + 1 })
      end

      @channel.acknowledge(hdr.delivery_tag, false)
    end
  end
end
