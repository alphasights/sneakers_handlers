# SneakersHandlers

The gem introduces three handlers you can use as part of your [`Sneakers`](https://github.com/jondot/sneakers) workers: 

* `SneakersHandlers::DeadLetterHandler`
* `SneakersHandlers::RetryHandler` 
* `SneakersHandlers::ExponentialBackoffHandler`.

`Sneakers` handlers are used to define custom behaviours to different scenarios (e.g. a success, error, timeout, etc.). 

By default `Sneakers` uses a handler called [`OneShot`](https://github.com/jondot/sneakers/blob/41883dd0df8b360c8d6e2f29101c960d5650f711/lib/sneakers/handlers/oneshot.rb) that,
as the name indicates, will try to execute the message only once, and `reject` it if something goes wrong. That can be fine for some workers, but we usually need something that will be able
to handle failed messages in a better way, either by sending them to a [dead-letter exchange](https://www.rabbitmq.com/dlx.html) or by trying to execute them again.

## Using the `DeadLetterHandler`

The `DeadLetterHandler` is an extension of the default `OneShot` handler. It will try to process the message only once, and when something goes wrong it will publish this message to the dead letter exchange.

When defining your worker, you have to define these extra arguments:

`x-dead-letter-exchange`: The name of the dead-letter exchange where failed messages will be published to.

`x-dead-letter-routing-key`: The routing key that will be used when dead-lettering a failed message. This value needs to be unique to your
application to avoid having the same message delivered to multiple queues. The recommendation is to use the queue name, although that's not mandatory.

Here's an example:

```diff
class DeadLetterWorker
  include Sneakers::Worker

  from_queue "sneakers_handlers.my_queue",
    ack: true,
    exchange: "sneakers_handlers",
    exchange_type: :topic,
    routing_key: "sneakers_handlers.dead_letter_test",
+   handler: SneakersHandlers::DeadLetterHandler,
+   arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
+                "x-dead-letter-routing-key" => "sneakers_handlers.my_queue" }

  def work(*args)
    ack!
  end
end
```

## Using the `RetryHandler`

The `RetryHandler` will try to execute the message `max_retry` times before dead-lettering it. The setup is very similar to the `DeadLetterHandler`, the only difference if that you can
also provide a `max_retry` argument, that will specify how many times the handler should try to execute this message.

```diff
class RetryWorker
  include Sneakers::Worker

  from_queue "sneakers_handlers.my_queue",
      ack: true,
      exchange: "sneaker_handlers",
      exchange_type: :topic,
      routing_key: "sneakers_handlers.retry_test",
+     handler: SneakersHandlers::RetryHandler,
+     max_retry: 50,
+     arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
+                  "x-dead-letter-routing-key" => "sneakers_handlers.my_queue" }

  def work(*args)
    ack!
  end
end
```

When a message fails, it will be published back to the end of the queue, so, assuming the queue is empty, there will be no delay (other than the network latency) between these retries.

## Using the `ExponentialBackoffHandler`

With this handler every retry is delayed by a power of 2 on the attempt number. The retry attempt is inserted into a new queue with a naming convention of `<queue name>.retry.<delay>`.
After exhausting the maximum number of retries (`max_retries`), the message will be moved into the dead letter exchange.

![backoff](https://github.com/alphasights/sneakers_handlers/blob/master/docs/backoff.png)

The setup is also very similar to the other handlers:

```diff
class ExponentialBackoffWorker
  include Sneakers::Worker

  from_queue "sneakers_handlers.my_queue",
      ack: true,
      exchange: "sneaker_handlers",
      exchange_type: :topic,
      routing_key: "sneakers_handlers.backoff_test",
+     handler: SneakersHandlers::ExponentialBackoffHandler,
+     max_retries: 50,
+     arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
+                  "x-dead-letter-routing-key" => "sneakers_handlers.my_queue" }

  def work(*args)
    ack!
  end
end
```

You can also customize the backoff function defining the `backoff_function` option, that can be any `call`able object (a lambda, a method, a class that responds to `call`, etc.)
that will receive the current attempt count and should return in how many seconds the message will be retried. 

```diff
class ExponentialBackoffWorker
  include Sneakers::Worker

  from_queue "sneakers_handlers.my_queue",
      ack: true,
      exchange: "sneaker_handlers",
      exchange_type: :topic,
      routing_key: "sneakers_handlers.backoff_test",
      handler: SneakersHandlers::ExponentialBackoffHandler,
+     backoff_function: ->(attempt_number) { attempt_number ** 3 },
      max_retries: 50,
      arguments: { "x-dead-letter-exchange" => "sneakers_handlers.dlx",
                   "x-dead-letter-routing-key" => "sneakers_handlers.my_queue" }

  def work(*args)
    ack!
  end
end
```

For a more detailed explanation of how the backoff handler works, check out the [blog post](https://m.alphasights.com/exponential-backoff-with-rabbitmq-78386b9bec81) we wrote about it.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sneakers_handlers'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sneakers_handlers

## Development

After checking out the repository, run `bin/setup` to install dependencies. Then, run `rake` to run the tests (you will need to have a real `RabbitMQ` instance running). You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).
