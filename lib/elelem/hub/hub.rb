# frozen_string_literal: true

module Elelem
  module Hub
    class Hub
      DEFAULT = "https://hub.elelem.sh"

      attr_reader :url, :web

      def initialize(url = ENV.fetch("ELELEM_HUB_URL", ""), web: Web.new)
        @url = (url.strip.empty? ? DEFAULT : url.strip).chomp("/")
        @web = web
        raise ArgumentError, "ELELEM_HUB_URL must be https, or http on loopback: #{@url}" unless Web.private?(@url)
      end

      def origin = URI(url).normalize.origin

      def name = "hub/#{origin}"

      def device
        web.get("#{url}/auth/device").tap do |device|
          raise KeyError, "#{origin} offers no sign-in" unless %w[issuer client_id audience].all? { device[it] }
        end
      end

      def models(token) = web.get("#{url}/v1/models", token:).fetch("data", []).map { it["id"] }

      def pick(models)
        raise KeyError, "no models on your nodes yet" if models.empty?

        models.first
      end
    end
  end
end
