# frozen_string_literal: true

module Elelem
  module Hub
    class Provider
      attr_reader :model

      def initialize(model: nil, http: nil, hub: Hub.new, secrets: Secrets.new)
        @model = model
        @http = http
        @hub = hub
        @token = Token.new(hub, secrets:)
      end

      def fetch(messages, tools = [], &) = openai.fetch(messages, tools, &)

      private

      def openai
        @openai ||= OpenAI::Provider.new(model: model || @hub.pick(@hub.models(@token.call)),
                                         key_command: method(:key), base_url: "#{@hub.url}/v1", http: @http)
      end

      def key = @key = @token.call(spent: @key)
    end
  end
end
