# frozen_string_literal: true

# The shared symbol registry, data/vocabulary.json in the format
# amath-vocabulary/v2 (amath#16 task 1, plurimath docs/pma.adoc "The
# registry v2 contract"). Read by scripts/generate_grammar.rb,
# scripts/generate_model.rb and scripts/check_reserved_words.rb.
#
# Every entry carries
#
#   category  the grammar list it belongs to (the v1 key it came from)
#   value     the v1 element: a spelling, a [spelling, class] pair, an
#             [open, close] pair, a [name, atom] pair or a character class
#   dialect   "legacy", "pma" or "both": the grammars generated from it
#   binding   a key of "bindings", each a map from the parse tree leaves
#             (captures) the entry produces to the model type of each
#
# The dialect L part is pinned by edition: the entries tagged "legacy" or
# "both", put back into the v1 layout, must serialize to exactly the bytes
# whose sha256 "legacy_edition" records. Those bytes are the v1 file the
# edition was taken from, so the dialect L grammar is generated from the
# same input as before registry v2, and an entry tagged "pma" can never
# reach it.
#
# Usage:
#   ruby scripts/registry.rb --check             verify the file and the pin
#   ruby scripts/registry.rb --legacy-v1 [OUT]   write the pinned v1 edition
#   ruby scripts/registry.rb --import-legacy V1  replace the dialect L
#     entries by those of a v1 export (scripts/export_vocabulary.rb), keep
#     the pma entries, and pin the result as the next legacy edition

require "digest"
require "json"

module Registry
  FORMAT = "amath-vocabulary/v2"
  LEGACY_FORMAT = "amath-vocabulary/v1"
  PATH = File.expand_path("../data/vocabulary.json", __dir__)
  DIALECTS = %w[legacy pma both].freeze

  # The v1 layout: key => how its entries fold back (:list, :pairs for a
  # Hash of [name, atom] entries, :scalar for a single entry).
  LEGACY_LAYOUT = {
    "precompile_constants" => :list,
    "unary_underscore_words" => :list,
    "ternary_classes" => :list,
    "binary_classes" => :list,
    "sub_sup_classes" => :list,
    "parenthesis" => :list,
    "table_parenthesis" => :list,
    "decimal_markers" => :list,
    "base_number_prefix" => :pairs,
    "symbol_char_class" => :scalar,
  }.freeze

  # Categories that only the pma grammar reads.
  PMA_CATEGORIES = %w[distribution_names].freeze

  # precompile_constants class => binding.
  CONSTANT_BINDINGS = {
    "symbol" => "symbol",
    "unary_class" => "unary_class",
    "fonts" => "fonts_class",
    "special_fonts" => "bold_fonts",
  }.freeze

  # Binding of every other legacy category (base_number_prefix: by name).
  CATEGORY_BINDINGS = {
    "unary_underscore_words" => "unary_class",
    "ternary_classes" => "ternary_class",
    "binary_classes" => "binary_class",
    "sub_sup_classes" => "binary_class",
    "parenthesis" => "paren",
    "table_parenthesis" => "table_paren",
    "decimal_markers" => "decimal_marker",
    "symbol_char_class" => "symbol",
  }.freeze

  module_function

  def load(path = PATH)
    data = JSON.parse(File.read(path, encoding: "UTF-8"))
    check!(data)
    data
  end

  def check!(data)
    abort "#{PATH}: format #{data['format'].inspect}, expected #{FORMAT}" unless data["format"] == FORMAT
    bindings = data.fetch("bindings")
    data.fetch("entries").each_with_index do |entry, i|
      where = "entry #{i} (#{entry['category']} #{entry['value'].inspect})"
      abort "#{where}: dialect #{entry['dialect'].inspect} is not one of #{DIALECTS.join(', ')}" unless DIALECTS.include?(entry["dialect"])
      abort "#{where}: binding #{entry['binding'].inspect} is not declared" unless bindings.key?(entry["binding"])
      known = LEGACY_LAYOUT.key?(entry["category"]) || PMA_CATEGORIES.include?(entry["category"])
      abort "#{where}: unknown category" unless known
      if PMA_CATEGORIES.include?(entry["category"]) && entry["dialect"] != "pma"
        abort "#{where}: category #{entry['category']} is read by the pma grammar only"
      end
    end
    bindings.each do |name, b|
      ok = b.is_a?(Hash) && !b.empty? && b.values.all?(String)
      abort "binding #{name}: must map capture names to model types" unless ok
    end
    pinned = data.fetch("legacy_edition").fetch("sha256")
    actual = "sha256:#{Digest::SHA256.hexdigest(legacy_bytes(data))}"
    return if actual == pinned

    abort "the dialect L entries no longer serialize to legacy edition " \
          "#{data['legacy_edition']['edition']} (#{pinned}, got #{actual}); " \
          "dialect L changes only through --import-legacy and a new edition"
  end

  # The entries one dialect's grammar is generated from, in file order.
  def entries(data, dialect)
    data.fetch("entries").select { |e| [dialect, "both"].include?(e["dialect"]) }
  end

  # The dialect L entries in the v1 layout, as the v1 export wrote them.
  def legacy_v1(data)
    out = { "format" => LEGACY_FORMAT, "oracle" => data.fetch("oracle") }
    grouped = entries(data, "legacy").group_by { |e| e["category"] }
    LEGACY_LAYOUT.each do |key, fold|
      values = grouped.fetch(key, []).map { |e| e["value"] }
      out[key] = case fold
                 when :list then values
                 when :pairs then values.to_h
                 when :scalar
                   abort "#{key} must have exactly one legacy entry" unless values.size == 1
                   values.first
                 end
    end
    out
  end

  def legacy_bytes(data)
    "#{JSON.pretty_generate(legacy_v1(data))}\n"
  end

  # Every spelling an entry puts into a grammar (for the reserved-word
  # check): spellings, class words, paren pairs and distribution names. The
  # [spelling, class] pairs contribute their spelling; prefix atoms and the
  # character class contribute no spelling.
  def spellings(data)
    data.fetch("entries").flat_map do |e|
      v = e["value"]
      case e["category"]
      when "precompile_constants" then [v.first]
      when "parenthesis", "table_parenthesis" then v
      when "base_number_prefix", "symbol_char_class" then []
      else [v]
      end
    end.uniq
  end

  # v1 hash => dialect L entries, in v1 order.
  def entries_from_v1(v1)
    LEGACY_LAYOUT.flat_map do |key, fold|
      values = case fold
               when :list then v1.fetch(key)
               when :pairs then v1.fetch(key).to_a
               when :scalar then [v1.fetch(key)]
               end
      values.map do |value|
        binding = case key
                  when "precompile_constants"
                    CONSTANT_BINDINGS.fetch(value.last) { abort "no binding for class #{value.last.inspect}" }
                  when "base_number_prefix" then value.first
                  else CATEGORY_BINDINGS.fetch(key)
                  end
        { "category" => key, "value" => value, "dialect" => "legacy", "binding" => binding }
      end
    end
  end

  # The file's bytes: pretty JSON with one entry per line.
  def dump(data)
    head = data.except("entries")
    text = JSON.pretty_generate(head.merge("entries" => ["@@ENTRIES@@"]))
    lines = data.fetch("entries").map { |e| "    #{JSON.generate(e)}" }
    "#{text.sub('    "@@ENTRIES@@"') { lines.join(",\n") }}\n"
  end

  def import_legacy!(v1_path, path = PATH)
    v1_bytes = File.binread(v1_path)
    v1 = JSON.parse(v1_bytes)
    abort "#{v1_path}: format #{v1['format'].inspect}, expected #{LEGACY_FORMAT}" unless v1["format"] == LEGACY_FORMAT
    abort "#{v1_path} is not in the canonical v1 layout" unless "#{JSON.pretty_generate(v1)}\n".b == v1_bytes

    data = JSON.parse(File.read(path, encoding: "UTF-8"))
    pma = data.fetch("entries").reject { |e| e["dialect"] == "legacy" }
    edition = data.fetch("legacy_edition").fetch("edition") + 1
    data["oracle"] = v1.fetch("oracle")
    data["legacy_edition"] = { "edition" => edition, "format" => LEGACY_FORMAT,
                               "sha256" => "sha256:#{Digest::SHA256.hexdigest(v1_bytes)}" }
    data["entries"] = entries_from_v1(v1) + pma
    File.write(path, dump(data))
    load(path)
    puts "wrote #{path}: legacy edition #{edition}"
  end
end

if $PROGRAM_NAME == __FILE__
  case ARGV.shift
  when "--check"
    data = Registry.load
    counts = Registry::DIALECTS.to_h { |d| [d, data["entries"].count { |e| e["dialect"] == d }] }
    puts "#{Registry::PATH}: #{data['entries'].size} entries #{counts}, " \
         "legacy edition #{data['legacy_edition']['edition']} #{data['legacy_edition']['sha256']}"
  when "--legacy-v1"
    bytes = Registry.legacy_bytes(Registry.load)
    ARGV.empty? ? $stdout.write(bytes) : File.binwrite(ARGV.first, bytes)
  when "--import-legacy"
    abort "usage: ruby scripts/registry.rb --import-legacy V1.json" unless ARGV.size == 1
    Registry.import_legacy!(ARGV.first)
  else
    abort "usage: ruby scripts/registry.rb --check | --legacy-v1 [OUT] | --import-legacy V1.json"
  end
end
