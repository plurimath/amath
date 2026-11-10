# frozen_string_literal: true

require "digest"
require "json"

module Amath
  # pma (dialect P, "plurimath ascii"), selected with
  # Amath.parse(input, dialect: :pma); specified by plurimath
  # docs/pma.adoc. It parses with its own artifact (artifacts/pma.json) and
  # never falls back to dialect L. The content of unit(...) is parsed by the
  # asciiunits artifact, the one whose checksum artifacts/pma.checksums.txt
  # records.
  #
  # Every refusal is an Amath::ParseError whose #category names the rule
  # the input breaks (Refusal::CATEGORIES); version 1 refuses every form
  # the specification leaves open.
  module Pma
    ENTRY = "document"
    ARTIFACT_PATH = File.expand_path("../../artifacts/pma.json", __dir__)
    CHECKSUMS_PATH = File.expand_path("../../artifacts/pma.checksums.txt", __dir__)
    UNITS_ENTRY = "expression"
    QUANTITIES_PATH = File.expand_path("../../data/quantities.json", __dir__)

    @artifact = Artifact.new(ARTIFACT_PATH, entries: [ENTRY])
    @units = nil
    @units_lock = Mutex.new
    @quantities = nil
    @quantities_lock = Mutex.new

    module_function

    def artifact
      @artifact
    end

    # The typed model (Amath::Model::PmaDocument) of +input+.
    def parse(input, decimal:, engine:)
      unless decimal == "."
        raise ArgumentError,
              "dialect: :pma has no decimal: option in version 1 " \
              "(got #{decimal.inspect}); numbers use the full stop"
      end

      text = Parser.normalize_input(input)
      mode = Engine.resolve(engine)
      tree = begin
        Engine.run(@artifact.fetch, ENTRY, text, mode, fallback: engine == :auto)
      rescue NestingTooDeep
        raise
      rescue ParseError => e
        raise Refusal.error(text, e.byte_offset, Refusal.category(text))
      end
      check_units(tree, text, mode)
      bound = @artifact.bindings.apply(ENTRY, tree)
      document = Model::PmaDocument.new(term: bound.fetch(:term))
      resolve_quantities(document.term)
      document
    end

    # The unitsdb quantities a quantity assertion may name: English name
    # => unitsml id (data/quantities.json, written by scripts/quantities.rb).
    def quantities
      @quantities_lock.synchronize { @quantities ||= load_quantities }
    end

    def load_quantities
      doc = JSON.parse(File.read(QUANTITIES_PATH))
      map = doc.fetch("quantities")
      unless doc.fetch("sha256") == "sha256:#{Digest::SHA256.hexdigest(JSON.generate(map))}"
        raise ArtifactError, "#{QUANTITIES_PATH} does not match its recorded sha256"
      end

      map
    rescue SystemCallError, JSON::ParserError, KeyError => e
      raise ArtifactError, "quantities cannot be loaded: #{e.class}: #{e.message}"
    end

    # The asciiunits artifact, checked against the checksum recorded when
    # the pma artifact was compiled.
    def units_artifact
      @units_lock.synchronize { @units ||= load_units }
    end

    def load_units
      require "asciiunits"
      expected = File.foreach(CHECKSUMS_PATH).find { |l| l.start_with?("asciiunits_artifact_checksum ") }
      raise ArtifactError, "#{CHECKSUMS_PATH} records no asciiunits artifact" unless expected

      expected = expected.split[1]
      actual = JSON.parse(File.read(Asciiunits::ARTIFACT_PATH)).fetch("checksum")
      unless actual == expected
        raise ArtifactError,
              "asciiunits artifact #{Asciiunits::ARTIFACT_PATH} has checksum #{actual}, " \
              "the pma artifact was composed with #{expected}"
      end

      Asciiunits.load_artifact
    rescue LoadError, SystemCallError, JSON::ParserError, KeyError, Parsanol::PARG::Error => e
      raise ArtifactError, "asciiunits artifact cannot be loaded: #{e.class}: #{e.message}"
    end

    # Every unit(...) text of +tree+ must be a non-empty asciiunits unit
    # expression (the grammar keeps `::` out of it), and a quantity
    # assertion after it must name a unitsdb quantity; an unknown name is
    # refused as a quantity assertion, at the name.
    def check_units(tree, text, mode)
      units_in(tree).each do |unit|
        slice = unit[:literal] || unit[:empty_list]
        start = byte_start(text, slice)
        raise Refusal.error(text, start, "unit-expression") unless unit[:literal]

        begin
          units_artifact.parse(UNITS_ENTRY, slice.to_s, mode: mode)
        rescue Parsanol::ParseFailed => e
          inner = ErrorPosition.byte_offset(e, units_artifact, UNITS_ENTRY, slice.to_s)
          raise Refusal.error(text, inner && (start + inner), "unit-expression")
        end
        next unless unit[:quantity]

        name = unit[:quantity]
        raise Refusal.error(text, byte_start(text, name), "quantity-assertion") unless quantities.key?(name.to_s)
      end
    end

    # Replaces the quantity name of every Unit of +term+ by the unitsml id
    # it resolves to (check_units has refused unknown names).
    def resolve_quantities(term)
      [term.unit, term.uncertainty&.unit, term.diff&.uncertainty&.unit].compact.each do |unit|
        unit.quantity = quantities.fetch(unit.quantity) if unit.quantity
      end
    end

    # Every `unit` capture of a raw tree ({literal:} or {empty_list:}).
    def units_in(node, out = [])
      case node
      when Hash
        node.each do |key, value|
          if key == :unit && value.is_a?(Hash)
            out << value
          else
            units_in(value, out)
          end
        end
      when Array then node.each { |v| units_in(v, out) }
      end
      out
    end

    # Byte offset of +slice+ in +text+ (Parsanol slice offsets count
    # characters).
    def byte_start(text, slice)
      text[0, slice.offset].bytesize
    end

    private_class_method :load_units, :load_quantities, :resolve_quantities, :units_in, :byte_start

    # The category of a refused pma input, from plurimath docs/pma.adoc
    # "Strict error taxonomy" (plus `no-production` for text that starts
    # no production at all). The first matching rule names it; the
    # position is the parser's.
    module Refusal
      CATEGORIES = %w[
        reserved-word adjacency constructor-arity constructor-argument
        measured-literal plus-minus-spelling shared-exponent relative
        distribution-tag concise unit-expression unit-attachment
        quantity-assertion no-production
      ].freeze

      CONSTRUCTORS = %w[ustd uexp ucov].freeze
      ARITY = { "ustd" => [2], "uexp" => [3, 4], "ucov" => [4, 5] }.freeze
      CALL_WORDS = /(?<![A-Za-z])(?:unit|ustd|uexp|ucov|diff)/
      WS = "[ \\t\\n\\r\\v\\f]"

      module_function

      def error(text, byte, category)
        char = byte && ErrorPosition.char_offset(text, byte)
        where = byte ? " at character #{char} (byte #{byte})" : ""
        ParseError.new("pma input rejected#{where}: #{category}",
                       input: text, byte_offset: byte, char_offset: char, category: category)
      end

      def category(text)
        return "reserved-word" if text.match?(/(?<![A-Za-z])quantity(?![A-Za-z])/)
        return "quantity-assertion" if text.include?("::")
        return "concise" if text.match?(/\d\(#{WS}*\d/o)

        bare = mask_units(text)
        rules(bare).each { |name, test| return name if test.call }
        "no-production"
      end

      def rules(bare)
        [
          ["plus-minus-spelling", -> { bare.match?(/\+-|±|(?<![A-Za-z])pm(?![A-Za-z])/) }],
          ["adjacency", -> { adjacency?(bare) }],
          ["reserved-word", -> { bare.match?(/#{CALL_WORDS}(?![A-Za-z(])/o) }],
          ["distribution-tag", -> { bare.include?("~") }],
          ["unit-attachment", -> { attachment?(bare) }],
          ["no-production", -> { bare.match?(/\A#{WS}*diff\(/o) && !bare.include?("unit(") }],
          ["shared-exponent", -> { bare.match?(/\)#{WS}*e/o) }],
          ["constructor-arity", -> { constructor(bare) == :arity }],
          ["constructor-argument", -> { constructor(bare) == :argument }],
          ["shared-exponent", -> { bare.match?(/\d[eE]/) }],
          ["relative", -> { bare.include?("%") }],
          ["measured-literal", -> { bare.include?("+/-") }],
          ["unit-expression", -> { bare.include?("unit(") }],
        ]
      end

      def adjacency?(bare)
        bare.match?(/#{CALL_WORDS}#{WS}+\(/o) ||
          bare.match?(/\)#{WS}+e[+-]?\d/o) ||
          bare.match?(%r{\+#{WS}+/|/#{WS}+-}o)
      end

      # Two units, a unit inside a constructor call, or a unit after a
      # plain number.
      def attachment?(bare)
        units = bare.scan("unit(").size
        return true if units > 1
        return false if units.zero?

        call = constructor_call(bare)
        return true if call && call[:args].any? { |a| a.include?("unit(") }

        before = bare[0, bare.index("unit(")].rstrip
        before.match?(/\d\z/) && !before.match?(/\)e[+-]?\d+\z/)
      end

      # :arity or :argument for a refused constructor call at the start of
      # the input (after an optional diff( ), else nil.
      def constructor(bare)
        call = constructor_call(bare)
        return nil unless call

        ARITY.fetch(call[:name]).include?(call[:args].size) ? :argument : :arity
      end

      def constructor_call(bare)
        m = bare.match(/\A#{WS}*(?:diff\(#{WS}*)?(ustd|uexp|ucov)\(/o)
        return nil unless m

        { name: m[1], args: arguments(bare[m.end(0)..]) }
      end

      # The top-level comma-separated arguments up to the matching ")".
      def arguments(rest)
        args = [+""]
        depth = 0
        rest.each_char do |c|
          break if c == ")" && depth.zero?

          depth += 1 if c == "("
          depth -= 1 if c == ")"
          c == "," && depth.zero? ? args << +"" : args.last << c
        end
        args
      end

      # +text+ with the content of every unit(...) replaced by "u", so that
      # unit names such as `pm` (picometre) match no other rule.
      def mask_units(text)
        out = +""
        i = 0
        while (j = text.index("unit(", i))
          out << text[i...j] << "unit("
          k = j + 5
          depth = 0
          while k < text.length
            c = text[k]
            break if c == ")" && depth.zero?

            depth += 1 if c == "("
            depth -= 1 if c == ")"
            out << "u"
            k += 1
          end
          i = k
        end
        out << text[i..]
      end
    end
  end
end
