# Using this handler, failed messages will be retried with an exponential
# backoff delay, for a certain number of times, until they are dead-lettered.
#
# To use it you need to defined this handler in your worker:
#
# from_queue "my-app.queue_name",
#   exchange: "my_exchange_name",
#   routing_key: "my_routing_key",
#   handler: SneakersHandlers::ExponentialBackoffHandler,
#   arguments: { "x-dead-letter-exchange" => "my_exchange_name.dlx",
#                "x-dead-letter-routing-key" => "my-app.queue_name" }}
#
# By default it will retry 25 times before dead-lettering a message, but you can
# also customize that with the `max_retries` option:
#
# from_queue "my-app.queue_name",
#   exchange: "my_exchange_name",
#   routing_key: "my_routing_key",
#   max_retries: 10,
#   handler: SneakersHandlers::ExponentialBackoffHandler,
#   arguments: { "x-dead-letter-exchange" => "my_exchange_name.dlx",
#                "x-dead-letter-routing-key" => "my-app.queue_name" }}

module SneakersHandlers
  class ExponentialBackoffHandler
    attr_reader :queue, :channel, :options, :max_retries

    DEFAULT_MAX_RETRY_ATTEMPTS = 25
    DEFAULT_BACKOFF_FUNCTION = -> (attempt_number) { (attempt_number + 1) ** 2 }

    def initialize(channel, queue, options)
      @queue = queue
      @channel = channel
      @options = options
      @max_retries = options[:max_retries] || DEFAULT_MAX_RETRY_ATTEMPTS
      @backoff_function  = options[:backoff_function] || DEFAULT_BACKOFF_FUNCTION

      create_error_exchange!

      queue.bind(primary_exchange, routing_key: queue.name)
    end

    def acknowledge(delivery_info, _, _)
      channel.acknowledge(delivery_info.delivery_tag, false)
    end

    def reject(delivery_info, properties, message, _requeue = true)
      retry_message(delivery_info, properties, message, :reject)
    end

    def error(delivery_info, properties, message, err)
      retry_message(delivery_info, properties, message, err)
    end

    def timeout(delivery_info, properties, message)
      retry_message(delivery_info, properties, message, :timeout)
    end

    def noop(_delivery_info, _properties, _message)
    end

    private

    def retry_message(delivery_info, properties, message, reason)
      attempt_number = death_count(properties[:headers])

      if attempt_number < max_retries
        delay = @backoff_function.call(attempt_number)

        log("msg=retrying, delay=#{delay}, count=#{attempt_number}, properties=#{properties}, reason=#{reason}")

        routing_key = "#{queue.name}.#{delay}"

        retry_queue = create_retry_queue!(delay)
        retry_queue.bind(primary_exchange, routing_key: routing_key)

        primary_exchange.publish(message, routing_key: routing_key, headers: properties[:headers])
        acknowledge(delivery_info, properties, message)
      else
        log("msg=erroring, count=#{attempt_number}, properties=#{properties}")
        channel.reject(delivery_info.delivery_tag)
      end
    end

    def death_count(headers)
      return 0 if headers.nil? || headers["x-death"].nil?

      headers["x-death"].inject(0) do |sum, x_death|
        sum + x_death["count"] if x_death["queue"] =~ /^#{queue.name}/
      end
    end

    def log(message)
      Sneakers.logger.info do
        "[#{self.class}] #{message}"
      end
    end

    def create_exchange(name)
      log("creating exchange=#{name}")

      channel.exchange(name, type: "topic", durable: options[:exchange_options][:durable])
    end

    def primary_exchange
      @primary_exchange ||= create_exchange("#{options[:exchange]}")
    end

    def create_error_exchange!
      arguments = options[:queue_options][:arguments]

      dlx_exchange_name = arguments.fetch("x-dead-letter-exchange")
      dlx_routing_key = arguments.fetch("x-dead-letter-routing-key")

      @error_exchange ||= create_exchange(dlx_exchange_name).tap do |exchange|
        queue = channel.queue("#{@queue.name}.error", durable: options[:queue_options][:durable])
        queue.bind(exchange, routing_key: dlx_routing_key)
      end
    end

    def create_retry_queue!(delay)
      clear_queues_cache
      channel.queue("#{queue.name}.retry.#{delay}",
         durable: options[:queue_options][:durable],
         arguments: {
           :"x-dead-letter-exchange" => options[:exchange],
           :"x-dead-letter-routing-key" => queue.name,
           :"x-message-ttl" => delay * 1_000,
           :"x-expires" => delay * 1_000 * 2
         }
        )
    end

    # When we create a new queue, `Bunny` stores its name in an internal cache.
    # The problem is that as we are creating ephemeral queues that can expire shortly
    # after they are created, this cached queue may not exist anymore when we try to
    # publish a second message to it.
    # Removing queues from the cache guarantees that `Bunny` will always try
    # to check if they exist, and when they don't, it will create them for us.
    def clear_queues_cache
      channel.queues.clear
    end
  end
end
