# frozen_string_literal: true

require "elelem"
require "elelem/openai"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "uri"

require_relative "hub/version"
require_relative "hub/secrets"
require_relative "hub/web"
require_relative "hub/tokens"
require_relative "hub/hub"
require_relative "hub/sign_in"
require_relative "hub/token"
require_relative "hub/provider"
require_relative "hub/account"

module Elelem
  module Hub
    def self.login(session, **) = Account.new(session, **).login

    def self.logout(session, **) = Account.new(session, **).logout
  end
end

Elelem.configure do |config|
  config.provider(:hub) { |model: nil, http: nil, **| Elelem::Hub::Provider.new(model:, http:) }
  config.setup(:hub) do |session|
    session.commands.register("login", description: "Sign in to the hub") { Elelem::Hub.login(session) }
    session.commands.register("logout", description: "Sign out of the hub") { Elelem::Hub.logout(session) }
  end
end
