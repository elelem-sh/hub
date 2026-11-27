# frozen_string_literal: true

module Elelem
  module Hub
    class Token
      def initialize(hub, secrets:, clock: Time)
        @hub = hub
        @secrets = secrets
        @clock = clock
      end

      def call
        renew
        raise KeyError, "signed out of #{@hub.origin}: type /login" unless @tokens

        @handed = @tokens.access_token
      end

      private

      def renew
        @secrets.update(@hub.name) { |saved| (@tokens = current(saved))&.to_json }
      rescue SystemCallError => e
        usable?(@tokens) ? Elelem.logger.warn("hub: could not save the sign-in: #{e.message}") : raise
      end

      def current(saved)
        newest = [@tokens, Tokens.parse(saved)].compact.max_by(&:expires_at)
        usable?(newest) ? newest : refresh(newest)
      end

      def usable?(tokens) = tokens&.fresh?(@clock.now) && tokens.access_token != @handed

      # RFC 6749 §6
      def refresh(stale)
        stale&.refresh_token && stale.renewed(grant(stale), @clock.now)
      rescue Web::Refusal => e
        raise unless e.code == "invalid_grant"
      end

      def grant(stale)
        @hub.web.form(stale.token_endpoint, grant_type: "refresh_token", refresh_token: stale.refresh_token,
                                            client_id: stale.client_id)
      end
    end
  end
end
