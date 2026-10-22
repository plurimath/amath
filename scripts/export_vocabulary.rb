# frozen_string_literal: true

# Build-time export of every piece of Ruby data that Plurimath's AsciiMath
# Parslet grammar (lib/plurimath/asciimath/parse.rb) turns into grammar
# alternatives. amath never loads Plurimath at runtime; this script runs once
# against a pinned Plurimath checkout and writes data/vocabulary.json, which
# scripts/generate_grammar.rb turns into grammars/asciimath.parg.
#
# Usage (from the Plurimath checkout, so its bundle is active):
#
#   cd PLURIMATH && bundle exec ruby -Ilib AMATH/scripts/export_vocabulary.rb \
#     [--out AMATH/data/vocabulary.json]
#
# The output is deterministic: same checkout + same Ruby => same bytes. It
# carries no timestamps. Arrays keep the oracle's effective alternative order;
# object keys are emitted in a fixed order.

require "json"
require "digest"
require "plurimath"

out = File.expand_path("../data/vocabulary.json", __dir__)
args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--out" then out = File.expand_path(args.shift)
  else abort "unknown argument #{arg.inspect}"
  end
end

root = File.expand_path(Gem.loaded_specs["plurimath"]&.full_gem_path || Dir.pwd)
root = Dir.pwd unless File.exist?(File.join(root, "lib/plurimath/asciimath/parse.rb"))
SOURCES = %w[
  lib/plurimath/asciimath/parse.rb
  lib/plurimath/asciimath/constants.rb
  lib/plurimath/base_number_prefix.rb
  lib/plurimath/utility.rb
  lib/plurimath/formatter/supported_locales.rb
  lib/plurimath/configuration.rb
].freeze

# The loaded Plurimath must be the checkout we hash.
loaded = $LOADED_FEATURES.find { |f| f.end_with?("/lib/plurimath/asciimath/parse.rb") }
loaded ||= Plurimath::Asciimath::Parse.instance_method(:read_text).source_location&.first
unless loaded && File.realpath(loaded) == File.realpath(File.join(root, SOURCES.first))
  abort "loaded Plurimath (#{loaded.inspect}) is not the checkout at #{root}; run with -Ilib from it"
end

revision = begin
  IO.popen(["git", "-C", root, "rev-parse", "HEAD"], err: File::NULL, &:read).strip
rescue StandardError
  ""
end

Constants = Plurimath::Asciimath::Constants
Parse = Plurimath::Asciimath::Parse

# Serialise a Parslet atom (only the kinds the base-prefix rules use).
def atom_json(atom)
  case atom
  when Parslet::Atoms::Entity then atom_json(atom.parslet)
  when Parslet::Atoms::Sequence then { "seq" => atom.parslets.map { |a| atom_json(a) } }
  when Parslet::Atoms::Alternative then { "alt" => atom.alternatives.map { |a| atom_json(a) } }
  when Parslet::Atoms::Named then { "as" => atom.name.to_s, "of" => atom_json(atom.parslet) }
  when Parslet::Atoms::Repetition
    { "repeat" => atom_json(atom.parslet), "min" => atom.min, "max" => atom.max }
  when Parslet::Atoms::Str then { "str" => atom.str }
  when Parslet::Atoms::Re then { "re" => atom.match }
  else abort "unsupported atom #{atom.class} in base-prefix rules"
  end
end

parser = Parse.new

# precompile_constants: [word, category] in the order hash_to_expression
# alternates them (sort_by length desc; ties as Ruby's sort_by leaves them).
vocabulary = Constants.precompile_constants.map { |word, category| [word.to_s, category.to_s] }

# The one negated character class in symbol_text_or_integer.
symbol_re = parser.symbol_text_or_integer.parslet.alternatives.filter_map do |alt|
  next unless alt.is_a?(Parslet::Atoms::Named) && alt.name == :symbol
  next unless alt.parslet.is_a?(Parslet::Atoms::Re)

  alt.parslet.match
end
abort "expected exactly one negated symbol class, got #{symbol_re.inspect}" unless symbol_re.size == 1

# unary_functions special-cases these words (compared via Str#to_s).
parse_src = File.read(File.join(root, SOURCES.first))
underscore = parse_src[/if \[(.*?)\]\.include\?\(first_value\.to_s\)/, 1]
abort "unary_functions underscore list not found in parse.rb" unless underscore
underscore_words = underscore.scan(/"'([^']+)'"/).flatten

markers = [Plurimath::Configuration::DEFAULT_DECIMAL]
Plurimath::Formatter::SupportedLocales::LOCALES.each_value do |symbols|
  markers << symbols[:decimal] if symbols[:decimal] && !markers.include?(symbols[:decimal])
end

data = {
  "format" => "amath-vocabulary/v1",
  "oracle" => {
    "repository" => "https://github.com/plurimath/plurimath",
    "revision" => revision,
    "ruby" => RUBY_VERSION,
    "parslet" => Gem.loaded_specs["parslet"]&.version&.to_s,
    "files" => SOURCES.to_h { |f| [f, "sha256:#{Digest::SHA256.file(File.join(root, f)).hexdigest}"] },
  },
  "precompile_constants" => vocabulary,
  "unary_underscore_words" => underscore_words,
  "ternary_classes" => Constants::TERNARY_CLASSES.map(&:to_s),
  "binary_classes" => Constants::BINARY_CLASSES.map(&:to_s),
  "sub_sup_classes" => Constants::SUB_SUP_CLASSES.map(&:to_s),
  "parenthesis" => Constants::PARENTHESIS.map { |k, v| [k.to_s, v.to_s] },
  "table_parenthesis" => Constants::TABLE_PARENTHESIS.map { |k, v| [k.to_s, v.to_s] },
  "decimal_markers" => markers,
  "base_number_prefix" => %i[hex_number binary_number octal_number].to_h do |name|
    [name.to_s, atom_json(parser.public_send(name))]
  end,
  "symbol_char_class" => symbol_re.first,
}

json = "#{JSON.pretty_generate(data)}\n"
File.binwrite(out, json)
warn "wrote #{out} (#{vocabulary.size} vocabulary entries, sha256:#{Digest::SHA256.hexdigest(json)})"
