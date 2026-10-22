# frozen_string_literal: true

require "amath"

SPIKE_ARTIFACT = File.expand_path("fixtures/spike.json", __dir__)

module EngineHelpers
  # Native-engine examples run wherever Parsanol's extension loads. With
  # AMATH_REQUIRE_NATIVE=1 (set in CI) a missing extension fails instead of
  # skipping.
  def require_native!
    return if Amath.native_available?
    raise "Parsanol native extension unavailable" if ENV["AMATH_REQUIRE_NATIVE"] == "1"

    skip "Parsanol native extension unavailable on #{RUBY_PLATFORM}"
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.include EngineHelpers

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    Amath.artifact_path = SPIKE_ARTIFACT
  end
end
