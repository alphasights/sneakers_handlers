# SneakersHandlers

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/sneakers_handlers`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sneakers_handlers'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sneakers_handlers

## Usage

The gem introduces two handlers you can use as part of your sneaker workers: `SneakersHandlers::DeadLetterHandler` and `SneakersHandlers::RetryHandler`

## Using the `SneakersHandlers::RetryHandler` handler

When defining your worker, you have the following extra options:

`x-dead-letter-exchange` [required] : The name of the dead-letter exchange
where failed messages will be published to.

`x-dead-letter-routing-key` [required] : The routing key that will be used when
dead-lettering a failed message. This value needs to be unique to your
application to avoid having the same message delivered to multiple queues. The
recommendation it to use the queue name.

`max_retry` [optional] : The number of times a message will be processed after
a rejection.


```ruby
class MyWorker
  include Sneakers::Worker
  from_queue "my-app.resource_processor",
      durable: true,
      ack: true,
      exchange: "domain_events",
      exchange_type: :topic,
      routing_key: "resources.lifecycle.*",
      handler: Sneakers::Handlers::RetryHandler,
      max_retry: 6,
      arguments: { "x-dead-letter-exchange" => "domain_events.dlx",
                   "x-dead-letter-routing-key" => "my-app.resource_processor" }

  def work(payload)
    ...
  end
end
```

## Using the `SneakersHandlers::ExponentialBackoffHandler` handler

When defining your worker, you have the following options:

`x-dead-letter-exchange` [required] : The name of the dead-letter exchange
where failed messages will be published to.

`x-dead-letter-routing-key` [required] : The routing key that will be used when
dead-lettering a failed message. This value needs to be unique to your
application to avoid having the same message delivered to multiple queues. The
recommendation it to use the queue name.

`max_retries` [optional] : An integer containing the maximum number of times
the same messages will be retried. If you don't define this option, `25` is the
default.

```ruby
class MyWorker
  include Sneakers::Worker
  from_queue "my-app.resource_processor",
      durable: true,
      ack: true,
      exchange: "domain_events",
      exchange_type: :topic,
      routing_key: "resources.lifecycle.*",
      handler: SneakersHandlers::ExponentialBackoffHandler,
      max_retries: 10,
      arguments: { "x-dead-letter-exchange" => "domain_events.dlx",
                   "x-dead-letter-routing-key" => "my-app.resource_processor" }

  def work(payload)
    ...
  end
end
```

### Backoff Behavior

Every retry is delayed by a power of 2 on the attempt number. The retry attempt is inserted into a new queue with a naming convention of `<queue name>.retry.<delay>`.

After exhausting the maximum number of retries (`max_retries`), the message will be moved into the dead letter exchange.

## Development

After checking out the repository, run `bin/setup` to install dependencies. Then, run `rake` to run the tests (you will need to have a real `RabbitMQ` instance running). You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).
