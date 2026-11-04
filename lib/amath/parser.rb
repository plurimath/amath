# frozen_string_literal: true

module Amath
  # Checks the arguments of Amath.parse, picks the artifact entry for the
  # decimal marker, hands the input to the engine and builds the model.
  module Parser
    module_function

    # The typed model (Amath::Model::Document) of +input+: the artifact's
    # declared binding (`root -> expression (any)`) gives the tree as plain
    # data, and lutaml-model builds the nested model from the declared
    # attribute types. Empty input is a Document without expression.
    def parse(input, decimal:, engine:)
      entry, text, tree = run(input, decimal: decimal, engine: engine)
      return Model::Document.new(decimal: decimal) if text.empty?

      bound = Amath.bindings.apply(entry, tree)
      Model::Document.new(expression: bound.fetch(:expression), decimal: decimal)
    end

    # Internal: the legacy-shaped raw tree of +input+ (Hash/Array of
    # Parsanol::Slice leaves, or a plain "" for empty input), as amath 0.1
    # returned it. See RawTree; not public API.
    def raw(input, decimal: ".", engine: :auto)
      RawTree.legacy(run(input, decimal: decimal, engine: engine).last)
    end

    # [entry, input text, tree of the normalized grammar].
    def run(input, decimal:, engine:)
      entry = entry_for(decimal)
      text = normalize_input(input)
      mode = Engine.resolve(engine)
      tree = Engine.run(Amath.artifact, entry, text, mode,
                        fallback: engine == :auto)
      [entry, text, tree]
    end

    # The bundled grammar's entry rules put the whole expression under one
    # `root` capture, the capture its declared bindings read. The tree
    # Amath returns is the expression itself, as before that capture
    # existed. An artifact without the capture (test fixtures) is returned
    # unchanged.
    def unwrap_root(tree)
      return tree unless tree.instance_of?(Hash) && tree.size == 1 && tree.key?(:root)

      tree[:root]
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
