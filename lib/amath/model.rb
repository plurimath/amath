# frozen_string_literal: true

require "lutaml/model"

module Amath
  # The typed AsciiMath model Amath.parse_model returns, declared with LutaML
  # Model. Its classes are generated from the normalized grammar's capture
  # shapes (scripts/generate_model.rb -> lib/amath/model/nodes.rb), except
  # MathSymbol and Document below. See docs/parser-contract.adoc.
  module Model
    # The derived +value+ and +kind+ of a class holding a catalog spelling.
    module Spelled
      # The portable declaration describes stored strings. Ruby keeps its
      # existing live spelling readers by refreshing those typed slots on
      # access, including after an in-place spelling edit. Target adapters
      # resolve the same catalog before constructing their generated models.
      def self.included(klass)
        klass.class_eval do
          def value
            @value = symbol_value
          end

          def kind
            @kind = symbol_kind
          end
        end
      end

      def symbol_value
        spelling && Symbols.lookup(spelling).value
      end

      def symbol_kind
        spelling && Symbols.lookup(spelling).kind
      end
    end

    # A catalog symbol: the text of a catalog capture (rule N9 puts it
    # under +spelling+), with the Unicode +value+ and +kind+ ("symbol",
    # "open", "close", "paren" or "unlisted") the legacy symbol lookup gives
    # it (Amath::Symbols). +value+ and +kind+ are derived from +spelling+.
    class MathSymbol < Lutaml::Model::Serializable
      attribute :spelling, :string
      attribute :value, :string
      attribute :kind, :string
      include Spelled

    end
  end
end

require_relative "model/nodes"

module Amath
  module Model
    # The result of one parse: the expression (nil for empty input) and
    # the decimal marker it was parsed with. Numbers keep their source
    # text, so "1,5" under decimal: "," is the number text "1,5".
    class Document < Lutaml::Model::Serializable
      attribute :expression, "Amath::Model::Expression"
      attribute :decimal, :string

    end

    # The result of one pma parse (Amath.parse_model(input, dialect: :pma)): the
    # one term pma version 1 reads. Its measured values are the same
    # Uncertainty (and Unit) classes dialect L builds.
    class PmaDocument < Lutaml::Model::Serializable
      attribute :term, "Amath::Model::Term"

    end

    # Every model class, in name order.
    def self.classes
      constants.sort.map { |c| const_get(c) }
               .select { |k| k.is_a?(Class) && k < Lutaml::Model::Serializable }
    end
  end
end
