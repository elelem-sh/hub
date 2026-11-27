# frozen_string_literal: true

RSpec.describe Elelem::Hub::Provider do
  let(:secrets) { Elelem::Hub::Secrets.new }
  let(:hub) { Elelem::Hub::Hub.new(web:) }
  let(:wire) { FakeWire.new }
  let(:models) { %w[qwen] }
  let(:grant) { { "access_token" => "new-access", "expires_in" => 3600 } }
  let(:web) do
    FakeWeb.new("https://hub.test/v1/models" => [{ "data" => models.map { { "id" => it } } }],
                "https://id.test/token" => [grant])
  end
  let(:tokens) do
    Elelem::Hub::Tokens.new(client_id: "cid", token_endpoint: "https://id.test/token", access_token: "old-access",
                            refresh_token: "old-refresh", expires_at: Time.now.to_i + 3600)
  end

  def provider(model: nil) = described_class.new(model:, http: wire, hub:, secrets:)

  def ask(provider) = provider.fetch([{ role: "user", content: "hi" }], [])

  def sign_in = secrets.update(hub.name) { tokens.to_json }

  it "starts while signed out, and says how to sign in at the first prompt" do
    provider = self.provider(model: "qwen")

    expect { ask(provider) }.to raise_error(KeyError, "signed out of https://hub.test: type /login")
    expect(wire.posts).to be_empty
  end

  it "sends the prompt through the hub with the access token" do
    sign_in
    ask(provider(model: "llama"))

    expect(wire.posts)
      .to eq([{ uri: "https://hub.test/v1/chat/completions", model: "llama", authorization: "Bearer old-access" }])
    expect(web.requests).to be_empty
  end

  it "uses the one model on your nodes when none is given" do
    sign_in
    ask(provider)

    expect(wire.posts.first).to include(model: "qwen", authorization: "Bearer old-access")
    expect(web.requests).to eq([["https://hub.test/v1/models", { token: "old-access" }]])
  end

  it "asks you to pick when your nodes have several models" do
    models.push("llama")
    sign_in

    expect { ask(provider) }.to raise_error(KeyError, "pick one: /provider hub MODEL (qwen, llama)")
  end

  it "refreshes the token the hub turned down, and asks again" do
    wire = FakeWire.new("HTTP 401: {}")
    sign_in
    ask(described_class.new(model: "qwen", http: wire, hub:, secrets:))

    expect(wire.posts.map { it[:authorization] }).to eq(["Bearer old-access", "Bearer new-access"])
  end
end
