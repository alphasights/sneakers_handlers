# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sneakers_handlers/version'

Gem::Specification.new do |spec|
  spec.name          = "sneakers_handlers"
  spec.version       = SneakersHandlers::VERSION
  spec.authors       = ["John Bohn, Abe Petrillo, Brian Storti"]
  spec.email         = ["abe.petrillo@gmail.com"]

  spec.summary       = %q{Adds Handlers to use with Sneakers}
  spec.description   = %q{Adds handlers to support retry and custom shoveling}
  spec.homepage      = "https://github.com/alphasights/sneakers_handlers"

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sneakers"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "dotenv"
end
