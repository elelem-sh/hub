# frozen_string_literal: true

RSpec.describe Elelem::Hub::Hub do
  subject(:hub) { described_class.new(web:) }

  let(:web) { FakeWeb.new }

  it "is hub.elelem.sh unless ELELEM_HUB_URL says otherwise" do
    ENV["ELELEM_HUB_URL"] = " "
    expect(described_class.new.url).to eq("https://hub.elelem.sh")

    ENV["ELELEM_HUB_URL"] = "http://127.0.0.1:8080/"
    expect(described_class.new.url).to eq("http://127.0.0.1:8080")
  end

  it "refuses a URL that would send tokens in the clear" do
    ENV["ELELEM_HUB_URL"] = "http://hub.elelem.sh"

    expect { described_class.new }
      .to raise_error(ArgumentError, "ELELEM_HUB_URL must be https, or http on loopback: http://hub.elelem.sh")
  end

  it "names its secrets by origin, so no two hubs share an entry" do
    names = %w[https://Hub.Test/ https://hub.test:443/x http://localhost:8080 https://localhost:8080]
            .map { described_class.new(it).name }

    expect(names).to eq(%w[hub/https://hub.test hub/https://hub.test hub/http://localhost:8080
                           hub/https://localhost:8080])
  end

  it "asks the hub how to sign in" do
    web = FakeWeb.new("https://hub.test/auth/device" => [FakeWeb::DEVICE, { "issuer" => FakeWeb::ISSUER }])
    hub = described_class.new(web:)

    expect(hub.device).to eq(FakeWeb::DEVICE)
    expect { hub.device }.to raise_error(KeyError, "https://hub.test offers no sign-in")
  end

  it "lists the models on your nodes" do
    web = FakeWeb.new("https://hub.test/v1/models" => [{ "data" => [{ "id" => "a" }, { "id" => "b" }] }])

    expect(described_class.new(web:).models("access")).to eq(%w[a b])
    expect(web.requests).to eq([["https://hub.test/v1/models", { token: "access" }]])
  end

  it "picks the first model, and says so when there is none" do
    expect(hub.pick(%w[a])).to eq("a")
    expect(hub.pick(%w[a b])).to eq("a")
    expect { hub.pick([]) }.to raise_error(KeyError, "no models on your nodes yet")
  end
end
