# frozen_string_literal: true

module Elelem
  module Hub
    class Token
      def initialize(hub, secrets:, clock: Time)
        @hub = hub
        @secrets = secrets
        @clock = clock
        @saved = true
      end

      def call(spent: nil)
        @spent = spent
        renew unless @saved && usable?(@tokens)
        @tokens&.access_token or raise KeyError, "signed out of #{@hub.origin}: type /login"
      end

      private

      def renew
        @saved = false
        @secrets.update(@hub.name) { |saved| (@tokens = current(saved))&.to_json }
        @saved = true
      rescue SystemCallError => e
        usable?(@tokens) ? Elelem.logger.warn("hub: could not save the sign-in: #{e.message}") : raise
      end

      def current(saved)
        newest = [@tokens, Tokens.parse(saved)].compact.max_by(&:expires_at)
        usable?(newest) ? newest : refresh(newest)
      end

      def usable?(tokens) = tokens&.fresh?(@clock.now) && tokens.access_token != @spent

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
