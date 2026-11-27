# frozen_string_literal: true

RSpec.describe Elelem::Hub::Account do
  let(:stream) { StringIO.new }
  let(:secrets) { Elelem::Hub::Secrets.new }
  let(:models) { %w[qwen] }
  let(:revocations) { [{}] }
  let(:grants) { [{ "access_token" => "sekret-access", "refresh_token" => "sekret-refresh", "expires_in" => 3600 }] }
  let(:hub) { Elelem::Hub::Hub.new(web:) }
  let(:web) do
    FakeWeb.signing_in(*grants).tap do |web|
      web.replies.update("https://hub.test/v1/models" => [{ "data" => models.map { { "id" => it } } }],
                         "https://id.test/revoke" => revocations)
    end
  end

  def session(provider_options = {})
    @session ||= Elelem::Config.build_session("hub", input: Elelem::NullInput.new, provider_options:,
                                                     output: Elelem::Output.new(stream:))
  end

  def account = described_class.new(session, hub:, secrets:, pause: ->(_) {})

  def saved = Elelem::Hub::Tokens.parse(secrets.fetch(hub.name))

  describe "#login" do
    it "says what you agree to and where to confirm, then saves the sign-in" do
      account.login

      expect(stream.string).to eq(<<~SAID)
        By signing in you agree to https://elelem.sh/terms/ and https://elelem.sh/privacy/
        open https://id.test/activate?user_code=WXYZ and confirm WXYZ
        signed in to https://hub.test, using qwen
      SAID
      expect(saved).to have_attributes(access_token: "sekret-access", refresh_token: "sekret-refresh")
    end

    it "gives the session a new provider with the model it started with" do
      started = session({ model: "llama" }).provider
      account.login

      expect(session.provider).to be_a(Elelem::Hub::Provider).and have_attributes(model: "llama")
      expect(session.provider).not_to be(started)
      expect(stream.string).to end_with("signed in to https://hub.test, using llama\n")
      expect(web.sent("https://hub.test/v1/models")).to be_empty
    end

    it "uses the first of several models and names the others" do
      models.push("llama", "gemma")
      account.login

      expect(stream.string).to end_with("using qwen (also llama, gemma: /provider hub MODEL)\n")
    end

    it "says so when there are no models to use" do
      models.clear
      account.login

      expect(stream.string).to end_with("signed in to https://hub.test: no models on your nodes yet\n")
    end

    it "saves nothing and keeps the provider when you say no" do
      grants.replace([Elelem::Hub::Web::Refusal.new("access_denied")])
      started = session.provider

      expect { account.login }.to raise_error(Elelem::Hub::Web::Refusal, "access_denied")
      expect(saved).to be_nil
      expect(session.provider).to be(started)
    end
  end

  describe "#logout" do
    before { account.login }

    it "revokes the refresh token, forgets the sign-in and drops the provider that held its key" do
      signed_in = session.provider
      account.logout

      expect(web.sent("https://id.test/revoke")).to eq([{ token: "sekret-refresh", client_id: "cid" }])
      expect(saved).to be_nil
      expect(session.provider).to be_a(Elelem::Hub::Provider)
      expect(session.provider).not_to be(signed_in)
      expect(stream.string).to end_with("signed out of https://hub.test\n")
    end

    it "forgets the sign-in even when the issuer cannot be told" do
      revocations.replace([Elelem::Hub::Web::Outage.new("POST https://id.test/revoke: 503")])
      account.logout

      expect(saved).to be_nil
      expect(stream.string).to end_with(<<~SAID)
        error: could not revoke the sign-in: POST https://id.test/revoke: 503
        signed out of https://hub.test
      SAID
    end

    it "leaves another provider in place" do
      session.provider = other = Object.new
      account.logout

      expect(session.provider).to be(other)
    end

    it "never says a token" do
      account.logout

      expect(stream.string).not_to include("sekret")
    end
  end

  it "signs out when nobody is signed in, without a word to the issuer" do
    account.logout

    expect(web.requests).to be_empty
    expect(stream.string).to eq("signed out of https://hub.test\n")
  end
end
