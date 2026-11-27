# frozen_string_literal: true

module Elelem
  module Hub
    class Account
      TERMS = "By signing in you agree to https://elelem.sh/terms/ and https://elelem.sh/privacy/"

      def initialize(session, hub: Hub.new, secrets: Secrets.new, pause: Kernel.method(:sleep))
        @session = session
        @hub = hub
        @secrets = secrets
        @pause = pause
      end

      def login
        say TERMS
        tokens = SignIn.new(@hub, show: method(:show), pause: @pause).call
        @secrets.update(@hub.name) { tokens.to_json }
        @session.provider = provider
        say "signed in to #{@hub.origin}#{using(tokens)}"
      end

      def logout
        saved = @secrets.fetch(@hub.name)
        @secrets.update(@hub.name) { nil }
        revoke(saved)
        @session.provider = provider if hub?
        say "signed out of #{@hub.origin}"
      end

      private

      def say(...) = @session.output.say(...)

      def show(url, code) = say("open #{url} and confirm #{code}")

      def hub? = @session.provider.is_a?(Provider)

      def model = (@session.provider.model if hub?)

      def provider = Provider.new(model:, hub: @hub, secrets: @secrets)

      def using(tokens)
        ", using #{model || @hub.pick(@hub.models(tokens.access_token))}"
      rescue KeyError => e
        ": #{e.message}"
      end

      # RFC 7009 §2.1
      def revoke(saved)
        tokens = Tokens.parse(saved)
        return unless tokens&.refresh_token

        @hub.web.form(tokens.revocation_endpoint, token: tokens.refresh_token, client_id: tokens.client_id)
      rescue StandardError => e
        say("could not revoke the sign-in: #{e.message}", as: :error)
      end
    end
  end
end
