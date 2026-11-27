# frozen_string_literal: true

module Elelem
  module Hub
    Tokens = Data.define(
      :client_id, :token_endpoint, :revocation_endpoint, :access_token, :refresh_token, :expires_at
    ) do
      def self.parse(json)
        json && new(**JSON.parse(json, symbolize_names: true))
      rescue JSON::ParserError, ArgumentError, TypeError
        raise KeyError, "the saved sign-in is unreadable: type /login"
      end

      def initialize(revocation_endpoint: nil, access_token: nil, refresh_token: nil, expires_at: 0, **) = super

      def to_json(*) = to_h.to_json(*)

      def inspect = "#<#{self.class} #{client_id}>"

      def fresh?(now) = expires_at - now.to_i >= 60

      def renewed(grant, now)
        with(
          access_token: grant.fetch("access_token") { raise Web::Outage, "the grant has no access_token" },
          refresh_token: grant["refresh_token"] || refresh_token,
          expires_at: now.to_i + lifetime(grant)
        )
      end

      private

      # RFC 6749 §5.1
      def lifetime(grant) = grant["expires_in"].to_i.then { it.positive? ? it : 300 }
    end
  end
end
