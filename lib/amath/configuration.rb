# frozen_string_literal: true

module Amath
  # Fixed settings: the artifact entries, the engine names and where the
  # bundled artifact lives. Amath re-exports each constant.
  module Configuration
    # Decimal marker => artifact entry name.
    DECIMAL_ENTRIES = {
      "." => "dot",
      "," => "comma",
      "٫" => "arabic", # ARABIC DECIMAL SEPARATOR
    }.freeze

    ENGINES = %i[auto native ruby].freeze

    # Deepest bracket nesting sent to the native engine off the main thread.
    THREAD_NATIVE_DEPTH = 25
    OPENING = "([{\u2112\u1455".chars.freeze
    CLOSING = ")]}\u211b\u1450".chars.freeze

    DEFAULT_ARTIFACT_PATH = File.expand_path("../../artifacts/asciimath.json",
                                             __dir__)
  end
end
