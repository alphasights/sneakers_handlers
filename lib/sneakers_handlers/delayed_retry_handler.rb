module SneakersHandlers
  class DelayedRetryHandler
    def initialize(channel, queue, options)
      @queue = queue

      @channel = channel
      @options = options

      @retry_exchange = exchange("#{options[:exchange]}.retry")
      @retry_queue = @channel.queue(retry_name,
        durable: durable_queues?,
        arguments: {
          "x-dead-letter-exchange": options[:exchange],
          "x-message-ttl": options[:retry_delay] || 5_000,
        }
      )

      @retry_queue.bind(@retry_exchange, routing_key: options[:routing_key])

      @error_exchange = exchange("#{options[:exchange]}.error")
      @error_queue = @channel.queue(error_name, durable: durable_queues?)
      @error_queue.bind(@error_exchange, routing_key: options[:routing_key])

      @max_retries = @options[:retry_max_times] || 5
    end

    def acknowledge(delivery_info, _, _)
      @channel.acknowledge(delivery_info.delivery_tag, false)
    end

    def reject(delivery_info, properties, message)
      retry_message(delivery_info, properties, message, :reject)
    end

    def error(delivery_info, properties, message, err)
      retry_message(delivery_info, properties, message, err)
    end

    def timeout(delivery_info, properties, message)
      retry_message(delivery_info, properties, message, :timeout)
    end

    def noop(delivery_info, properties, message); end

    private

    def retry_message(delivery_info, properties, message, reason)
      attempt_number = death_count(properties[:headers])

      if attempt_number < @max_retries
        log("msg=retrying, count=#{attempt_number}, properties=#{properties}")

        @channel.reject(delivery_info.delivery_tag, false)
      else
        log("msg=erroring, count=#{attempt_number}, properties=#{properties}")

        @error_exchange.publish(message, routing_key: delivery_info[:routing_key])
        acknowledge(delivery_info, properties, message)
      end
    end

    def death_count(headers)
      return 0 if headers.nil? || headers["x-death"].nil?

      headers["x-death"].inject(0) do |sum, x_death|
        sum + x_death["count"] if x_death["queue"] == primary_name
      end
    end

    def primary_name
      @queue.name
    end

    def retry_name
      "#{primary_name}.retry"
    end

    def error_name
      "#{primary_name}.error"
    end

    def exchange(name)
      log("creating exchange=#{name}")

      @channel.exchange(name, type: "topic", durable: durable_exchanges?)
    end

    def log(message)
      Sneakers.logger.debug do
        "DelayedRetryHandler handler [queue=#{@primary_queue_name}] #{message}"
      end
    end

    def durable_exchanges?
      @options[:exchange_options][:durable]
    end

    def durable_queues?
      @options[:queue_options][:durable]
    end
  end
end
