module SneakersHandlers
  class ExponentialBackoffHandler
    attr_reader :queue, :channel, :options, :delays

    def initialize(channel, queue, options)
      @queue = queue
      @channel = channel
      @options = options
      @delays = options[:delays] || [1.second, 10.seconds, 1.minute, 10.minutes]

      Array(@options[:routing_key]).each do |key|
        queue.bind(primary_exchange, routing_key: key + ".*")
      end
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

      routing_key_segments = delivery_info[:routing_key].split(".")
      routing_key_segments.pop if Integer(routing_key_segments.last) rescue nil

      if attempt_number < @delays.length
        delay = @delays[attempt_number]

        log("msg=retrying, delay=#{delay}, count=#{attempt_number}, properties=#{properties}")

        routing_key_segments << delay
        routing_key = routing_key_segments.join(".")

        retry_queue = create_retry_queue!(delay)
        retry_queue.bind(retry_exchange, routing_key: routing_key)

        retry_exchange.publish(message, routing_key: routing_key, headers: properties[:headers])
      else
        log("msg=erroring, count=#{attempt_number}, properties=#{properties}")

        error_exchange.publish(message, routing_key: delivery_info[:routing_key])
      end

      acknowledge(delivery_info, properties, message)
    end

    def death_count(headers)
      return 0 if headers.nil? || headers["x-death"].nil?

      headers["x-death"].inject(0) do |sum, x_death|
        sum + x_death["count"] if x_death["queue"] =~ /^#{queue.name}/
      end
    end

    def log(message)
      Sneakers.logger.debug do
        "DelayedRetryHandler handler [queue=#{@primary_queue_name}] #{message}"
      end
    end

    def durable_exchanges?
      options[:exchange_options][:durable]
    end

    def durable_queues?
      options[:queue_options][:durable]
    end

    def create_exchange(name)
      log("creating exchange=#{name}")

      @channel.exchange(name, type: "topic", durable: durable_exchanges?)
    end

    def retry_exchange
      @retry_exchange ||= create_exchange("#{options[:exchange]}.retry")
    end

    def primary_exchange
      @primary_exchange ||= create_exchange("#{options[:exchange]}")
    end

    def error_exchange
      @error_exchange ||= create_exchange("#{options[:exchange]}.error").tap do |exchange|
        queue = @channel.queue("#{@queue.name}.error", durable: durable_queues?)

        Array(@options[:routing_key]).each do |key|
          queue.bind(exchange, routing_key: key)
          queue.bind(exchange, routing_key: key + ".*")
        end
      end
    end

    def create_retry_queue!(delay)
      @channel.queue("#{queue.name}.retry.#{delay}",
        durable: durable_queues?,
        arguments: {
          :"x-dead-letter-exchange" => options[:exchange],
          :"x-message-ttl" => delay * 1_000,
          :"x-expires" => delay * 1_000 * 2
        }
      )
    end
  end
end
