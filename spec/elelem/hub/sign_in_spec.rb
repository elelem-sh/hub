# frozen_string_literal: true

RSpec.describe Elelem::Hub::SignIn do
  let(:shown) { [] }
  let(:waits) { [] }
  let(:clock) { Struct.new(:now).new(Time.at(1000)) }
  let(:grant) { { "access_token" => "access", "refresh_token" => "refresh", "expires_in" => 3600 } }
  let(:pending) { refusal("authorization_pending") }
  let(:slow_down) { refusal("slow_down") }
  let(:outage) { Elelem::Hub::Web::Outage.new("POST https://id.test/token: 503") }

  def refusal(code) = Elelem::Hub::Web::Refusal.new(code)

  def sign_in(web)
    described_class.new(Elelem::Hub::Hub.new(web:), show: ->(*said) { shown << said }, pause: waits.method(:push),
                                                    clock:).call
  end

  it "shows where to confirm the code, waits for it, and returns the tokens" do
    web = FakeWeb.signing_in(pending, grant)

    expect(sign_in(web)).to eq(
      Elelem::Hub::Tokens.new(client_id: "cid", token_endpoint: "https://id.test/token",
                              revocation_endpoint: "https://id.test/revoke", access_token: "access",
                              refresh_token: "refresh", expires_at: 4600)
    )
    expect(shown).to eq([["https://id.test/activate?user_code=WXYZ", "WXYZ"]])
    expect(waits).to eq([5, 5])
  end

  it "asks for a device code for the hub, then redeems it" do
    web = FakeWeb.signing_in(grant)
    sign_in(web)

    expect(web.sent("https://id.test/device"))
      .to eq([{ client_id: "cid", audience: "https://hub.test", scope: "openid offline_access" }])
    expect(web.sent("https://id.test/token"))
      .to eq([{ grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code: "dc", client_id: "cid" }])
  end

  it "polls as often as the issuer asks, and shows the plain address when that is all there is" do
    code = FakeWeb::CODE.merge("interval" => 2).except("verification_uri_complete")
    sign_in(FakeWeb.signing_in(pending, grant, code:))

    expect(shown).to eq([["https://id.test/activate", "WXYZ"]])
    expect(waits).to eq([2, 2])
  end

  it "slows down when told to" do
    sign_in(FakeWeb.signing_in(slow_down, pending, grant))

    expect(waits).to eq([5, 10, 10])
  end

  it "slows down through an outage, until the code has expired" do
    sign_in(FakeWeb.signing_in(outage, grant))
    expect(waits).to eq([5, 10])

    expired = FakeWeb.signing_in(outage, outage, code: FakeWeb::CODE.merge("expires_in" => 15))
    expect { sign_in(expired) }.to raise_error(outage)
    expect(waits).to eq([5, 10, 5, 10])
  end

  it "stops when you say no" do
    web = FakeWeb.signing_in(pending, refusal("access_denied"), grant)

    expect { sign_in(web) }.to raise_error(Elelem::Hub::Web::Refusal, "access_denied")
    expect(waits).to eq([5, 5])
  end

  it "stops when the code expires" do
    expect { sign_in(FakeWeb.signing_in(refusal("expired_token"))) }
      .to raise_error(Elelem::Hub::Web::Refusal, "expired_token")
  end

  it "trusts no issuer but the one the hub names" do
    web = FakeWeb.signing_in(grant, found: FakeWeb::FOUND.merge("issuer" => "https://id.test"))

    expect { sign_in(web) }
      .to raise_error("discovery names the issuer https://id.test, the hub names https://id.test/")
    expect(web.sent("https://id.test/device")).to be_empty
  end
end
