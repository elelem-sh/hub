# frozen_string_literal: true

require_relative "lib/elelem/hub/version"

Gem::Specification.new do |spec|
  spec.name = "elelem-hub"
  spec.version = Elelem::Hub::VERSION
  spec.authors = ["mo khan"]
  spec.email = ["mo@mokhan.ca"]

  spec.summary = "Sign in to an elelem hub and use your own nodes from elelem."
  spec.description = "An elelem plugin that signs in to an elelem hub and sends prompts through it to your own nodes."
  spec.homepage = "https://elelem.sh"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/elelem-sh/hub"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["LICENSE.txt", "lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "elelem", ">= 0.19", "< 1"
  spec.add_dependency "elelem-openai", ">= 0.5", "< 1"
end
