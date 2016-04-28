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

`max_retry` [optional] : The number of times a message will be processed after a rejection

`x-dead-letter-routing-key` [mandatory] : The routing key that the retry queue will be bound to, usually it is the name of the original queue, for example:

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

Exponential Backoff isn't really the right phrase for this. It's more
static configurable backoff. Plan on updating the name in the future.

When defining your worker, you have the following extra options:

`delay` [required] : An array containing the number of seconds to pause between retries

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
      delay: [1.second, 10.seconds, 1.minute, 10.minutes]

  def work(payload)
    ...
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/sneakers_handlers.
