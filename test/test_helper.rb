$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require "sneakers_handlers"
require "minitest/autorun"
require "minitest/reporters"
require "sneakers"
require 'pry-byebug'

Minitest::Reporters.use! Minitest::Reporters::DefaultReporter.new(color: true)

Sneakers.configure
Sneakers.logger.level = Logger::ERROR
