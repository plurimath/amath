# frozen_string_literal: true

# The legacy AsciiMath symbol lookup -> data/asciimath-symbols.json
#
# Usage (once per oracle revision, like scripts/export_vocabulary.rb):
#
#   BUNDLE_GEMFILE=<a Gemfile with `gem "plurimath", path: ORACLE`> \
#     bundle exec ruby scripts/export_symbols.rb --oracle ORACLE [--check]
#
# ORACLE is a clean Plurimath checkout at the revision data/vocabulary.json
# records (the grammar's oracle). With --check the export is compared with
# the committed file instead of written; it exits 1 when they differ.
#
# The legacy transform turns the text of a catalog capture (symbol, comma,
# parens and the other captures the grammar puts under `spelling`) into a
# Plurimath object with
#
#   Asciimath::Utility.asciimath_symbol_object(text)
#     symbols_hash(:asciimath)[text]                  exact text, a symbol
#     || all_symbols_classes(:asciimath)[text.strip]  after mapping the
#                                                     four table parens
#     || Math::Symbols::Symbol.new(text)
#
# This export writes that lookup out, one record per spelling the tables
# list, so amath resolves symbols without loading Plurimath:
#
#   spelling  the text, as the tables key it
#   value     the Unicode text of the MathML the resolved class writes
#   mathml    that MathML element ("mi" or "mo")
#   kind      "symbol", or for a Plurimath paren "open", "close" or "paren"
#   class     the Plurimath class, relative to Plurimath::Math::Symbols
#   padded    present only where the lookup of the text with surrounding
#             whitespace (all_symbols_classes, where a paren wins) resolves
#             to another class: that class's value, mathml, kind and class
#
# plus the four table parens the transform renames before the lookup
# (ℒ ℛ ᑕ ᑐ). A text no record lists stays a plain symbol of its own text;
# that rule is amath's (Amath::Symbols), not data. Records are sorted by
# spelling (byte order), so the file is a pure function of the oracle.

require "digest"
require "json"
require "open3"
require "optparse"

ROOT = File.expand_path("..", __dir__)
DATA = File.join(ROOT, "data/asciimath-symbols.json")
VOCAB = File.join(ROOT, "data/vocabulary.json")
FORMAT = "amath-symbols/v1"
PREFIX = "Plurimath::Math::Symbols::"

def git(dir, *args)
  out, status = Open3.capture2("git", "-C", dir, *args)
  abort "git #{args.join(' ')} failed in #{dir}" unless status.success?
  out.strip
end

def verify!(oracle, revision)
  head = git(oracle, "rev-parse", "HEAD")
  abort "#{oracle} is at #{head}, expected #{revision} (data/vocabulary.json)" unless head == revision
  dirty = git(oracle, "status", "--porcelain", "--untracked-files=no")
  abort "#{oracle} has local changes" unless dirty.empty?
end

def kind(object)
  return "symbol" unless object.is_a?(Plurimath::Math::Symbols::Paren)
  return "open" if object.open?
  return "close" if object.close?

  "paren"
end

# value, mathml, kind and class of a resolved legacy object.
def describe(object)
  node = object.to_mathml_without_math_tag(nil)
  text = node.nodes
  unless text.size == 1 && text.first.is_a?(String)
    abort "#{object.class} writes MathML that is not one element with one text node"
  end
  abort "#{object.class} is outside #{PREFIX}" unless object.class.name.start_with?(PREFIX)

  { "value" => Plurimath::Utility.html_entity_to_unicode(text.first),
    "mathml" => node.name, "kind" => kind(object),
    "class" => object.class.name.delete_prefix(PREFIX) }
end

def export(oracle)
  oracle_doc = JSON.parse(File.read(VOCAB)).fetch("oracle")
  verify!(oracle, oracle_doc.fetch("revision"))
  $LOAD_PATH.unshift(File.join(oracle, "lib"))
  require "plurimath"
  loaded = $LOADED_FEATURES.grep(%r{/lib/plurimath\.rb\z}).first
  abort "plurimath was loaded from #{loaded}, not #{oracle}" unless loaded&.start_with?(oracle)

  # The AsciiMath helpers subclass Plurimath::Utility (same tables).
  utility = Plurimath::Asciimath::Utility
  table = utility.all_symbols_classes(:asciimath)
  spellings = table.keys | utility.symbols_hash(:asciimath).keys
  renamed = %w[ℒ ℛ ᑕ ᑐ] - spellings
  records = (spellings + renamed).map do |spelling|
    record = { "spelling" => spelling }.merge(describe(utility.asciimath_symbol_object(spelling)))
    next record if renamed.include?(spelling)

    padded = describe(utility.asciimath_symbol_object(" #{spelling} "))
    record["padded"] = padded unless padded["class"] == record["class"]
    record
  end
  records.sort_by! { |r| r["spelling"].b }

  {
    "format" => FORMAT,
    "oracle" => {
      "repository" => oracle_doc.fetch("repository"),
      "revision" => oracle_doc.fetch("revision"),
      "lib_tree" => git(oracle, "rev-parse", "HEAD:lib"),
      "ruby" => RUBY_VERSION,
      "source" => "Plurimath::Asciimath::Utility.asciimath_symbol_object over the spellings of " \
                  "all_symbols_classes(:asciimath) and symbols_hash(:asciimath)",
    },
    "counts" => {
      "spellings" => records.size,
      "classes" => records.map { |r| r["class"] }.uniq.size,
      "kinds" => records.map { |r| r["kind"] }.tally.sort.to_h,
      "padded" => records.count { |r| r.key?("padded") },
    },
    "symbols" => records,
  }
end

# One record per line keeps diffs of the 3,000-odd records readable.
def dump(data)
  head = data.except("symbols")
  lines = data.fetch("symbols").map { |r| "    #{JSON.generate(r)}" }
  body = JSON.pretty_generate(head).delete_suffix("\n}")
  "#{body},\n  \"symbols\": [\n#{lines.join(",\n")}\n  ]\n}\n"
end

options = { oracle: nil, check: false }
OptionParser.new do |o|
  o.banner = "usage: ruby scripts/export_symbols.rb --oracle DIR [--check]"
  o.on("--oracle DIR", "pinned Plurimath checkout") { |v| options[:oracle] = File.expand_path(v) }
  o.on("--check", "compare with data/asciimath-symbols.json instead of writing") { options[:check] = true }
end.parse!(ARGV)
abort "unexpected arguments #{ARGV.inspect}" unless ARGV.empty?
abort "--oracle DIR is required" unless options[:oracle]

data = dump(export(options[:oracle]))
if options[:check]
  abort "stale: #{DATA}" unless File.exist?(DATA) && File.binread(DATA) == data.b
  puts "up to date"
else
  File.write(DATA, data)
  puts "wrote #{DATA.delete_prefix("#{ROOT}/")} (#{data.bytesize} bytes) sha256:#{Digest::SHA256.hexdigest(data)}"
end
