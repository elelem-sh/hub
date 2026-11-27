# frozen_string_literal: true

module Elelem
  module Hub
    class SignIn
      SCOPE = "openid offline_access"
      DEVICE_CODE = "urn:ietf:params:oauth:grant-type:device_code"
      SLOWER = { "authorization_pending" => 0, "slow_down" => 5 }.freeze

      def initialize(hub, show:, pause: Kernel.method(:sleep), clock: Time)
        @hub = hub
        @show = show
        @pause = pause
        @clock = clock
      end

      def call
        client = client(@hub.device)
        code = authorize(client)
        @show.call(code["verification_uri_complete"] || code["verification_uri"], code["user_code"])
        tokens(client).renewed(await(client, code), @clock.now)
      end

      private

      def client(device)
        issuer = device.fetch("issuer")
        found = @hub.web.get("#{issuer.chomp("/")}/.well-known/openid-configuration")
        raise "discovery names the issuer #{found["issuer"]}, the hub names #{issuer}" unless found["issuer"] == issuer

        found.merge(device).transform_keys(&:to_sym)
      end

      # RFC 8628 §3.1
      def authorize(client)
        @hub.web.form(client.fetch(:device_authorization_endpoint), scope: SCOPE, **client.slice(:client_id, :audience))
      end

      def tokens(client) = Tokens.new(**client.slice(:client_id, :token_endpoint, :revocation_endpoint))

      # RFC 8628 §3.5
      def await(client, code, interval = seconds(code["interval"], 5), left = seconds(code["expires_in"], 900))
        @pause.call(interval)
        redeem(client, code)
      rescue Web::Refusal, Web::Outage => e
        left -= interval
        interval += slower(e, left)
        retry
      end

      # RFC 8628 §3.4
      def redeem(client, code)
        @hub.web.form(client.fetch(:token_endpoint), grant_type: DEVICE_CODE, device_code: code.fetch("device_code"),
                                                     client_id: client.fetch(:client_id))
      end

      def slower(failure, left)
        return SLOWER.fetch(failure.code) { raise failure } if failure.is_a?(Web::Refusal)

        left.positive? ? SLOWER.fetch("slow_down") : raise(failure)
      end

      def seconds(given, default) = given.to_i.positive? ? given.to_i : default
    end
  end
end
