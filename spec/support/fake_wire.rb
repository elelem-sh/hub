# frozen_string_literal: true

class FakeWire
  attr_reader :posts

  def initialize(*failures)
    @failures = failures
    @posts = []
  end

  def post(uri, body:, headers: {})
    @posts << { uri: uri.to_s, model: body[:model], authorization: headers["authorization"] }
    raise @failures.shift unless @failures.empty?
  end
end
