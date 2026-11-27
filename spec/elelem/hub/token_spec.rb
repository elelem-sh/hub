# frozen_string_literal: true

RSpec.describe Elelem::Hub::Token do
  let(:clock) { Struct.new(:now).new(Time.at(1000)) }
  let(:secrets) { Elelem::Hub::Secrets.new }
  let(:web) { FakeWeb.new("https://id.test/token" => grants) }
  let(:hub) { Elelem::Hub::Hub.new(web:) }
  let(:grants) { [{ "access_token" => "new-access", "refresh_token" => "new-refresh", "expires_in" => 3600 }] }
  let(:fresh) { stale.with(expires_at: 4600) }
  let(:stale) do
    Elelem::Hub::Tokens.new(client_id: "cid", token_endpoint: "https://id.test/token", access_token: "old-access",
                            refresh_token: "old-refresh", expires_at: 1000)
  end
  let(:full_disk) do
    Class.new(Elelem::Hub::Secrets) do
      def update(name, &block)
        return super unless (@full = !@full)

        block.call(fetch(name))
        raise Errno::ENOSPC
      end
    end
  end

  def token(secrets: self.secrets) = described_class.new(hub, secrets:, clock:)

  def save(tokens) = secrets.update(hub.name) { tokens.to_json }

  def saved = Elelem::Hub::Tokens.parse(secrets.fetch(hub.name))

  it "hands out the saved access token while it is fresh" do
    save(fresh)

    expect(token.call).to eq("old-access")
    expect(web.requests).to be_empty
  end

  it "says how to sign in when nothing is saved" do
    expect { token.call }.to raise_error(KeyError, "signed out of https://hub.test: type /login")
  end

  it "refreshes a stale access token, and saves the rotated refresh token" do
    save(stale)

    expect(token.call).to eq("new-access")
    expect(web.sent("https://id.test/token"))
      .to eq([{ grant_type: "refresh_token", refresh_token: "old-refresh", client_id: "cid" }])
    expect(saved).to eq(stale.with(access_token: "new-access", refresh_token: "new-refresh", expires_at: 4600))
  end

  it "keeps the refresh token when the grant has no new one" do
    grants.first.delete("refresh_token")
    save(stale)
    token.call

    expect(saved.refresh_token).to eq("old-refresh")
  end

  it "refreshes once, however many ask" do
    save(stale)

    expect([token, token].map(&:call)).to eq(%w[new-access new-access])
    expect(web.requests.size).to eq(1)
  end

  it "hands out the token it holds without reading it again" do
    save(fresh)
    token = self.token
    token.call
    save(fresh.with(access_token: "other-access"))

    expect(token.call).to eq("old-access")
  end

  it "refreshes a fresh token the hub turned down" do
    save(fresh)

    expect(token.call(spent: "old-access")).to eq("new-access")
    expect(saved.access_token).to eq("new-access")
  end

  it "takes the token another process refreshed in place of the one turned down" do
    save(fresh.with(access_token: "other-access"))

    expect(token.call(spent: "old-access")).to eq("other-access")
    expect(web.requests).to be_empty
  end

  it "forgets the sign-in when the issuer no longer honours it" do
    grants.replace([Elelem::Hub::Web::Refusal.new("invalid_grant", "Unknown or invalid refresh token.")])
    save(stale)

    expect { token.call }.to raise_error(KeyError, "signed out of https://hub.test: type /login")
    expect(saved).to be_nil
  end

  it "is signed out once a stale token has nothing to refresh it" do
    save(stale.with(refresh_token: nil))

    expect { token.call }.to raise_error(KeyError, "signed out of https://hub.test: type /login")
    expect(web.requests).to be_empty
  end

  it "keeps the sign-in through an outage or any other refusal" do
    failures = [Elelem::Hub::Web::Outage.new("POST https://id.test/token: 503"),
                Elelem::Hub::Web::Refusal.new("invalid_client")]
    grants.replace(failures.dup)
    save(stale)

    failures.each { |failure| expect { token.call }.to raise_error(failure) }
    expect(saved).to eq(stale)
  end

  it "keeps a refreshed token it could not save, and saves it at the next call" do
    save(stale)
    token = self.token(secrets: full_disk.new)

    expect(token.call).to eq("new-access")
    expect(saved).to eq(stale)

    expect(token.call).to eq("new-access")
    expect(saved.refresh_token).to eq("new-refresh")
    expect(web.requests.size).to eq(1)
  end

  it "fails when it cannot reach the saved sign-in at all" do
    locked_out = Class.new(Elelem::Hub::Secrets) { def update(*) = raise(Errno::EACCES) }

    expect { token(secrets: locked_out.new).call }.to raise_error(Errno::EACCES)
  end
end
