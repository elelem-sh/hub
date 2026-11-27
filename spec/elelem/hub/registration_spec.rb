# frozen_string_literal: true

RSpec.describe "the hub plugin" do
  let(:stream) { StringIO.new }
  let(:wire) { FakeWire.new }
  let(:session) do
    Elelem::Config.build_session("hub", input: Elelem::NullInput.new, output: Elelem::Output.new(stream:))
  end

  it "starts a session while signed out, with /login and /logout" do
    expect(session.provider).to be_a(Elelem::Hub::Provider)
    expect(session.commands.to_h).to include("/login" => "Sign in to the hub", "/logout" => "Sign out of the hub")
  end

  it "signs out of the hub that ELELEM_HUB_URL names" do
    ENV["ELELEM_HUB_URL"] = "http://127.0.0.1:8080"
    session.commands.run("logout")

    expect(stream.string).to eq("signed out of http://127.0.0.1:8080\n")
  end

  it "sends prompts to the hub, with the saved sign-in and the model asked for" do
    tokens = Elelem::Hub::Tokens.new(client_id: "cid", token_endpoint: "https://id.test/token",
                                     access_token: "access", expires_at: Time.now.to_i + 3600)
    Elelem::Hub::Secrets.new.update("hub/https://hub.test") { tokens.to_json }
    Elelem::Config.build_provider("hub", model: "qwen", http: wire).fetch([{ role: "user", content: "hi" }], [])

    expect(wire.posts)
      .to eq([{ uri: "https://hub.test/v1/chat/completions", model: "qwen", authorization: "Bearer access" }])
  end
end
