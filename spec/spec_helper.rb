# frozen_string_literal: true

require_relative "../lib/elelem/hub"

Dir[File.join(__dir__, "support/**/*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.around do |example|
    saved = ENV.to_h
    Dir.mktmpdir do |home|
      ENV.update("XDG_CONFIG_HOME" => home, "ELELEM_HUB_URL" => "https://hub.test",
                 "ELELEM_LOG" => "-", "ELELEM_LOG_LEVEL" => "fatal")
      example.run
    end
  ensure
    ENV.replace(saved)
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
