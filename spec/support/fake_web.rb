# frozen_string_literal: true

class FakeWeb
  ISSUER = "https://id.test/"
  DEVICE = { "issuer" => ISSUER, "client_id" => "cid", "audience" => "https://hub.test" }.freeze
  FOUND = { "issuer" => ISSUER, "device_authorization_endpoint" => "https://id.test/device",
            "token_endpoint" => "https://id.test/token", "revocation_endpoint" => "https://id.test/revoke" }.freeze
  CODE = { "device_code" => "dc", "user_code" => "WXYZ", "verification_uri" => "https://id.test/activate",
           "verification_uri_complete" => "https://id.test/activate?user_code=WXYZ" }.freeze

  attr_reader :requests, :replies

  def self.signing_in(*grants, code: CODE, found: FOUND)
    new("https://hub.test/auth/device" => [DEVICE], "https://id.test/.well-known/openid-configuration" => [found],
        "https://id.test/device" => [code], "https://id.test/token" => grants)
  end

  def initialize(replies = {})
    @replies = replies
    @requests = []
  end

  def get(url, token: nil) = answer(url, { token: }.compact)

  def form(url, **fields) = answer(url, fields)

  def sent(url) = requests.filter_map { |to, fields| fields if to == url }

  private

  def answer(url, fields)
    @requests << [url, fields]
    reply = @replies.fetch(url, []).shift or raise "nothing to answer #{url}"
    reply.is_a?(Exception) ? raise(reply) : reply
  end
end
