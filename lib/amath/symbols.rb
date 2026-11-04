# frozen_string_literal: true

require "json"

module Amath
  # The legacy AsciiMath symbol lookup, exported once from Plurimath by
  # scripts/export_symbols.rb into data/asciimath-symbols.json: for every
  # spelling the legacy tables list, the Unicode value, MathML element,
  # kind and Plurimath class the legacy transform resolves it to.
  #
  # Lookup follows Asciimath::Utility.asciimath_symbol_object: the exact
  # text first; text with surrounding whitespace resolves as its stripped
  # text, through the record's +padded+ resolution where the legacy tables
  # resolve that differently. Text no record lists is an unlisted symbol of
  # its own text.
  module Symbols
    DATA_PATH = File.expand_path("../../data/asciimath-symbols.json", __dir__)
    Entry = Struct.new(:value, :mathml, :kind, :klass, keyword_init: true)

    @lock = Mutex.new

    module_function

    # spelling => record, loaded once.
    def catalog
      @catalog || @lock.synchronize do
        @catalog ||= JSON.parse(File.read(DATA_PATH, encoding: "UTF-8"))
                         .fetch("symbols").to_h { |r| [r.fetch("spelling"), r] }.freeze
      end
    end

    # The Entry for +text+ (a catalog capture's spelling).
    def lookup(text)
      record = catalog[text]
      return entry(record) if record

      stripped = text.strip
      record = catalog[stripped] unless stripped == text
      return entry(record.fetch("padded", record)) if record

      Entry.new(value: text, mathml: nil, kind: "unlisted", klass: nil)
    end

    def entry(record)
      Entry.new(value: record.fetch("value"), mathml: record.fetch("mathml"),
                kind: record.fetch("kind"), klass: record.fetch("class"))
    end
  end
end
