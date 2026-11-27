# frozen_string_literal: true

RSpec.describe Elelem::Hub::Tokens do
  subject(:tokens) do
    described_class.new(client_id: "cid", token_endpoint: "https://id.test/token", access_token: "old-access",
                        refresh_token: "old-refresh", expires_at: 1000)
  end

  it "survives a round trip through JSON, and parses nothing as nothing" do
    expect(described_class.parse(tokens.to_json)).to eq(tokens)
    expect(described_class.parse(nil)).to be_nil
  end

  it "calls anything else unreadable, without quoting it" do
    ["sekret{", '{"sekret":1}', "[1]"].each do |saved|
      expect { described_class.parse(saved) }.to raise_error(KeyError, "the saved sign-in is unreadable: type /login")
    end
  end

  it "is fresh until a minute before it expires" do
    expect(tokens.fresh?(Time.at(940))).to be(true)
    expect(tokens.fresh?(Time.at(941))).to be(false)
  end

  it "takes the access token, the rotated refresh token and the lifetime from a grant" do
    grant = { "access_token" => "new-access", "refresh_token" => "new-refresh", "expires_in" => 3600 }

    expect(tokens.renewed(grant, Time.at(2000)))
      .to eq(tokens.with(access_token: "new-access", refresh_token: "new-refresh", expires_at: 5600))
  end

  it "keeps its refresh token when the grant has none, and trusts an undated grant for five minutes" do
    expect(tokens.renewed({ "access_token" => "new-access" }, Time.at(2000)))
      .to eq(tokens.with(access_token: "new-access", expires_at: 2300))
  end

  it "calls a grant with no access token an outage" do
    expect { tokens.renewed({}, Time.at(2000)) }.to raise_error(Elelem::Hub::Web::Outage)
  end

  it "keeps its tokens out of sight" do
    expect(tokens.inspect).to eq("#<Elelem::Hub::Tokens cid>")
  end
end
