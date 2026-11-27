# frozen_string_literal: true

module Elelem
  module Hub
    class Web
      LOOPBACK = /\A(localhost|127(\.\d{1,3}){3}|::1)\z/
      BROKEN = [SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError,
                Net::ProtocolError, Net::HTTPBadResponse].freeze

      class Outage < StandardError; end

      class Refusal < StandardError
        attr_reader :code

        def self.of(fields, status, asked)
          error = fields["error"]
          code, said = error.is_a?(Hash) ? error.values_at("code", "message") : [error, fields["error_description"]]
          new(code || status, said || asked)
        end

        def initialize(code, said = nil)
          @code = code
          super([code, said].compact.join(": "))
        end
      end

      def self.private?(url)
        uri = URI(url.to_s)
        uri.scheme == "https" ? !uri.host.to_s.empty? : uri.scheme == "http" && LOOPBACK.match?(uri.hostname)
      rescue URI::InvalidURIError
        false
      end

      def initialize(open_timeout: 10, read_timeout: 30)
        @timeouts = { open_timeout:, read_timeout: }
      end

      def get(url, token: nil)
        ask(Net::HTTP::Get.new(private(url), { "authorization" => ("Bearer #{token}" if token) }.compact))
      end

      def form(url, **fields)
        ask(Net::HTTP::Post.new(private(url)).tap { it.set_form_data(fields) })
      end

      private

      def private(url)
        Web.private?(url) ? URI(url) : raise(ArgumentError, "#{url} must be https, or http on loopback")
      end

      def ask(request)
        request["accept"] = "application/json"
        answer(deliver(request), "#{request.method} #{request.uri}")
      end

      def deliver(request)
        uri = request.uri
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", **@timeouts) { it.request(request) }
      rescue *BROKEN => e
        raise Outage, "#{request.method} #{uri}: #{e.message}"
      end

      def answer(response, asked)
        fields = fields(response.body)
        raise Refusal.of(fields.to_h, response.code, asked) if response.is_a?(Net::HTTPClientError)
        raise Outage, "#{asked}: #{response.code} #{response.message}" unless fields && response.is_a?(Net::HTTPSuccess)

        fields
      end

      def fields(body)
        Hash(JSON.parse(body.to_s.empty? ? "{}" : body))
      rescue JSON::ParserError, TypeError
        nil
      end
    end
  end
end
