# frozen_string_literal: true

module Amath
  # Checks the arguments of Amath.parse, picks the artifact entry for the
  # decimal marker and hands the input to the engine.
  module Parser
    module_function

    def parse(input, decimal:, engine:)
      entry = entry_for(decimal)
      text = normalize_input(input)
      mode = Engine.resolve(engine)
      tree = Engine.run(Amath.artifact, entry, text, mode,
                        fallback: engine == :auto)
      Renester.call(tree)
    end

    def entry_for(decimal)
      Configuration::DECIMAL_ENTRIES.fetch(decimal) do
        raise ArgumentError,
              "unsupported decimal marker #{decimal.inspect} " \
              "(supported: #{Configuration::DECIMAL_ENTRIES.keys.map(&:inspect).join(', ')})"
      end
    end

    # +input+ as valid UTF-8, or an ArgumentError.
    def normalize_input(input)
      unless input.is_a?(String)
        raise ArgumentError,
              "input must be a String, got #{input.class}"
      end

      text = input.encoding == Encoding::UTF_8 ? input : input.encode(Encoding::UTF_8)
      unless text.valid_encoding?
        raise ArgumentError,
              "input is not valid UTF-8"
      end

      text
    rescue EncodingError => e
      raise ArgumentError, "input cannot be converted to UTF-8: #{e.message}"
    end
  end
end
