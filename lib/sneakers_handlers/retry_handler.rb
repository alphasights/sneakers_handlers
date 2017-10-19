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
#   arguments: { "x-dead-letter-exchange" => "dlx.domain_events",
#                "x-dead-letter-routing-key" => "my-app.queue_name" }}

module SneakersHandlers
  class RetryHandler

    def initialize(channel, queue, options)
      @channel = channel
      @queue = queue
      @routing_key = options[:routing_key]
      @max_retry = options[:max_retry] || 5

      create_dlx(channel, queue, options)
    end

    def acknowledge(hdr, _props, _msg)
      @channel.acknowledge(hdr.delivery_tag, false)
    end

    def reject(hdr, props, msg, requeue = false)
      retry_message(hdr, props, msg, :reject)
    end

    def error(hdr, props, msg, err)
      retry_message(hdr, props, msg, err.inspect)
    end

    def timeout(hdr, props, msg)
      retry_message(hdr, props, msg, :timeout)
    end

    def noop(_hdr, _props, _msg)
    end

    private

    def create_dlx(channel, queue, options)
      arguments = options[:queue_options][:arguments]

      dlx_exchange_name = arguments.fetch("x-dead-letter-exchange")
      dlx_exchange = channel.exchange(dlx_exchange_name, {
        type: "topic",
        durable: options[:exchange_options][:durable],
      })

      @dlx_queue = channel.queue("#{queue.name}.error", durable: options[:queue_options][:durable])
      @dlx_queue.bind(dlx_exchange, routing_key: arguments.fetch("x-dead-letter-routing-key"))
    end

    def retry_message(hdr, props, msg, reason)
      headers = props[:headers] || {}
      retry_count = headers["x-retry-count"] || 1
      if retry_count >= @max_retry
        @channel.reject(hdr.delivery_tag)
      else
        Sneakers.logger.info do
          "Retrying message: queue=#{@queue.name} retry_count=#{retry_count} reason=#{reason}."
        end

        headers = headers.merge({ "x-retry-count": retry_count + 1, "rejection_reason": reason.to_s })
        @channel.default_exchange.publish(msg,
                                          routing_key: @queue.name,
                                          headers: headers)
        @channel.acknowledge(hdr.delivery_tag, false)
      end
    end
  end
end
