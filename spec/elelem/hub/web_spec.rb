# frozen_string_literal: true

require "socket"

RSpec.describe Elelem::Hub::Web do
  subject(:web) { described_class.new(open_timeout: 2, read_timeout: 2) }

  let(:server_class) do
    Class.new do
      attr_reader :requests

      def initialize(*replies)
        @replies = replies
        @requests = []
        @server = TCPServer.new("127.0.0.1", 0)
        @thread = Thread.new { loop { serve(@server.accept) } }
      end

      def url(path = "/") = "http://127.0.0.1:#{@server.addr[1]}#{path}"

      def stop
        @thread.kill
        @server.close
      end

      private

      def serve(socket)
        head = socket.gets("\r\n\r\n")
        @requests << (head + socket.read(head[/content-length: (\d+)/i, 1].to_i))
        socket.write(@replies.shift)
      ensure
        socket.close
      end
    end
  end

  def reply(status, body, headers = "")
    "HTTP/1.1 #{status}\r\ncontent-length: #{body.bytesize}\r\nconnection: close\r\n#{headers}\r\n#{body}"
  end

  def serving(*replies)
    server = server_class.new(*replies)
    yield server
  ensure
    server.stop
  end

  it "gets JSON, asking for it and sending the token as a bearer" do
    serving(reply("200 OK", '{"data":[]}')) do |server|
      expect(web.get(server.url("/v1/models"), token: "sekret")).to eq("data" => [])
      expect(server.requests.first).to start_with("GET /v1/models HTTP/1.1")
        .and match(%r{^accept: application/json\r$}i)
        .and match(/^authorization: Bearer sekret\r$/i)
    end
  end

  it "posts a form, and takes an empty answer as no fields" do
    serving(reply("200 OK", "")) do |server|
      expect(web.form(server.url("/oauth/revoke"), token: "a b", client_id: "c")).to eq({})
      expect(server.requests.first).to start_with("POST /oauth/revoke HTTP/1.1")
        .and match(%r{^content-type: application/x-www-form-urlencoded\r$}i)
        .and end_with("\r\n\r\ntoken=a+b&client_id=c")
    end
  end

  it "refuses any URL that is not https or loopback http" do
    expect(%w[https://hub.elelem.sh http://localhost:1 http://127.0.0.1 http://[::1]:8080/x])
      .to all(satisfy { described_class.private?(it) })
    expect(["http://hub.elelem.sh", "http://127.0.0.1.evil.test", "ftp://localhost", "https://", "not a url", nil])
      .to all(satisfy { !described_class.private?(it) })
    expect { web.get("http://hub.elelem.sh/auth/device") }
      .to raise_error(ArgumentError, "http://hub.elelem.sh/auth/device must be https, or http on loopback")
  end

  it "names an OAuth refusal by its code" do
    denied = '{"error":"access_denied","error_description":"You said no"}'
    serving(reply("403 Forbidden", denied)) do |server|
      expect { web.form(server.url) }.to raise_error(described_class::Refusal, "access_denied: You said no") { |e|
        expect(e.code).to eq("access_denied")
      }
    end
  end

  it "names a hub refusal by its code, and any other by its status" do
    rejected = '{"error":{"code":"invalid_api_key","message":"Sign in again"}}'
    serving(reply("401 Unauthorized", rejected), reply("404 Not Found", "<html>")) do |server|
      expect { web.get(server.url) }.to raise_error(described_class::Refusal, "invalid_api_key: Sign in again")
      expect { web.get(server.url) }.to raise_error(described_class::Refusal, "404: GET #{server.url}")
    end
  end

  it "calls a failing server an outage, without quoting what it said" do
    serving(reply("503 Service Unavailable", "sekret"), reply("200 OK", "sekret")) do |server|
      2.times do
        expect { web.get(server.url) }.to raise_error(described_class::Outage) { |e|
          expect(e.message).to start_with("GET #{server.url}: ").and(satisfy { !it.include?("sekret") })
        }
      end
    end
  end

  it "follows no redirect" do
    serving(reply("302 Found", "", "location: https://elsewhere.test/\r\n")) do |server|
      expect { web.get(server.url) }.to raise_error(described_class::Outage, "GET #{server.url}: 302 Found")
      expect(server.requests.size).to eq(1)
    end
  end

  it "calls a server that cannot be reached an outage" do
    closed = serving(&:url)

    expect { web.get(closed) }.to raise_error(described_class::Outage, /\AGET #{Regexp.escape(closed)}: /)
  end
end
