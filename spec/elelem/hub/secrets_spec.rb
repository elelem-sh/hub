# frozen_string_literal: true

RSpec.describe Elelem::Hub::Secrets do
  subject(:secrets) { described_class.new(path) }

  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  let(:path) { File.join(@dir, "elelem", "hub.json") }

  def mode(file) = File.stat(file).mode & 0o777

  def child
    fork do
      yield
      exit!(0)
    end
  end

  it "has nothing until a name is updated, and forgets a name updated to nil" do
    expect(secrets.fetch("hub/a")).to be_nil

    expect(secrets.update("hub/a") { "one" }).to eq("one")
    secrets.update("hub/b") { |value| "#{value}two" }
    expect(described_class.new(path).fetch("hub/a")).to eq("one")

    secrets.update("hub/a") { nil }
    expect(JSON.parse(File.read(path))).to eq("hub/b" => "two")
  end

  it "keeps the directory and its files to their owner" do
    secrets.update("hub/a") { "one" }

    expect(mode(File.dirname(path))).to eq(0o700)
    expect([path, "#{path}.lock"].map { mode(it) }).to eq([0o600, 0o600])
  end

  it "writes nothing when the value stays the same" do
    secrets.update("hub/a") { nil }

    expect(File.exist?(path)).to be(false)
  end

  it "refuses a file it cannot parse, without quoting or replacing it" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "sekret{")

    expect { secrets.fetch("hub/a") }.to raise_error(IOError, "#{path} is not a JSON object: fix it or remove it")
    expect { secrets.update("hub/a") { "one" } }.to raise_error(IOError)
    expect(File.read(path)).to eq("sekret{")
  end

  it "runs one update at a time across processes" do
    inside, release, ready, seen = Array.new(4) { IO.pipe }
    first = child { secrets.update("hub/a") { [inside.last.puts, release.first.gets, "first"].last } }
    inside.first.gets
    second = child { [ready.last.puts, secrets.update("hub/a") { |value| [seen.last.puts(value), "second"].last }] }
    ready.first.gets
    release.last.puts

    expect([first, second].map { Process.wait2(it).last }).to all(be_success)
    expect(seen.first.gets).to eq("first\n")
    expect(secrets.fetch("hub/a")).to eq("second")
  end
end
