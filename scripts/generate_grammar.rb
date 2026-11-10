# frozen_string_literal: true

# data/vocabulary.json (legacy edition) + grammars/asciimath.parg.template
#   -> grammars/asciimath.parg                    the grammar Parsanol compiles
#   -> grammars/asciimath.wrappers.json           the captures the shape
#                                                 normalization added
#   -> grammars/asciimath.normalized-rules.json   the normalized rule tree
#
# Usage: ruby scripts/generate_grammar.rb [--check]
#   --check  exit 1 if a committed output differs from a fresh generation
#
# Needs Parsanol (its PARG parser reads the expanded template), not
# Plurimath. Output is a pure function of the two inputs (no timestamps).
#
# The vocabulary is the registry's pinned dialect L edition
# (scripts/registry.rb): its entries tagged legacy or both, in the v1 layout,
# byte for byte the v1 file the edition was taken from. The header's
# "data/vocabulary.json sha256:" line is the sha256 of those edition bytes.
# Entries tagged pma never reach this grammar.
#
# Steps:
#   1. expand the template with the vocabulary (one rule per line)
#   2. read every rule with Parsanol's PARG parser into a rule tree
#      (scripts/parg_rule_tree.rb)
#   3. normalize capture shapes (shared rules N1-N7 of
#      scripts/normalize_shapes.rb, amath rules N8-N9 of scripts/amath_shapes.rb),
#      so that every capture holds one kind; generation stops on a capture
#      that still holds two kinds or only nil
#   4. write each rewritten rule back in place of its line, and check that
#      the written grammar reads back as exactly the normalized rule tree

require "json"
require "digest"
require "set"
require_relative "parg_rule_tree"
require_relative "amath_shapes"
require_relative "registry"

ROOT = File.expand_path("..", __dir__)
VOCAB = File.join(ROOT, "data/vocabulary.json")
TEMPLATE = File.join(ROOT, "grammars/asciimath.parg.template")
OUT = File.join(ROOT, "grammars/asciimath.parg")
# Read by the internal raw-tree unwrap (Amath::RawTree) and the model
# generator (scripts/generate_model.rb).
WRAPPERS_OUT = File.join(ROOT, "grammars/asciimath.wrappers.json")
NORMALIZED_OUT = File.join(ROOT, "grammars/asciimath.normalized-rules.json")
NORMALIZED_FORMAT = "amath-normalized-rules/1"
# The entry rule of every decimal marker; its `root` capture is the tree.
ROOT_RULE = "document"

# Captures whose text the legacy transform resolves through the symbol
# catalog (Utility.asciimath_symbol_object): N9 puts that text under
# `spelling`, and the model types it as a MathSymbol.
CATALOG = %w[symbol comma lparen rparen left right table_left table_right d x].freeze

# Decimal marker -> entry name. A marker without a name here stops generation.
MARKER_ENTRIES = { "." => "dot", "," => "comma", "٫" => "arabic" }.freeze

class Generator
  def initialize(vocab_bytes, template)
    @vocab_bytes = vocab_bytes
    @data = JSON.parse(vocab_bytes)
    @template = template
    abort "unsupported vocabulary format #{@data['format']}" unless @data["format"] == "amath-vocabulary/v1"
  end

  def generate
    parts = {
      "header" => header,
      "decimal_doc" => decimal_doc,
      "ternary_classes" => named_list("ternary_classes", @data["ternary_classes"], "ternary_class"),
      "binary_classes" => named_list("binary_classes", @data["binary_classes"], "binary_class"),
      "sub_sup_classes" => named_list("sub_sup_classes", @data["sub_sup_classes"], "binary_class"),
      "open_table" => named_list("open_table", @data["table_parenthesis"].map(&:first), "table_left"),
      "close_table" => named_list("close_table", @data["table_parenthesis"].map(&:last), "table_right"),
      "lparen" => rule("lparen", @data["parenthesis"].map { |o, _| lit(o) }),
      "rparen" => rule("rparen", @data["parenthesis"].map { |_, c| lit(c) }),
      "symbol_char" => symbol_char,
      "read_text" => read_text,
      "decimal_marker" => decimal_marker,
      "base_number_prefix" => base_number_prefix,
      "vocabulary" => vocabulary,
      "vocabulary_rules" => @vocab_rules.join("\n"),
      "entries" => entries,
    }
    used = []
    out = @template.each_line.filter_map do |line|
      next if line.start_with?("#!")

      if (m = line.match(/\A\s*\{\{(\w+)\}\}\s*\z/))
        used << m[1]
        parts.fetch(m[1]) { abort "unknown placeholder #{m[1]}" }.then { |t| "#{t}\n" }
      elsif line.lstrip.start_with?("#")
        line
      else
        # Inline placeholders (inside a rule line).
        line.gsub(/\{\{(\w+)\}\}/) do
          used << ::Regexp.last_match(1)
          parts.fetch(::Regexp.last_match(1)) { abort "unknown placeholder #{::Regexp.last_match(1)}" }
        end
      end
    end.join
    missing = parts.keys - used
    abort "placeholders not used by the template: #{missing.join(', ')}" unless missing.empty?
    out = specialise!(out)
    bad = out.each_line.with_index(1).reject { |l, _| l.ascii_only? }.map(&:last)
    abort "generated grammar is not pure ASCII (lines #{bad.first(5).join(', ')})" unless bad.empty?
    out
  end

  private

  def header
    o = @data["oracle"]
    lines = ["# GENERATED by scripts/generate_grammar.rb -- do not edit.",
             "# Plurimath AsciiMath grammar (#{o['repository']} @ #{o['revision']}),",
             "# exported with Ruby #{o['ruby']} / Parslet #{o['parslet']}.",
             "# data/vocabulary.json sha256:#{Digest::SHA256.hexdigest(@vocab_bytes)}",
             "# oracle source files:"]
    o["files"].each { |f, sum| lines << "#   #{f} #{sum}" }
    lines.join("\n")
  end

  def decimal_doc
    markers.map do |m|
      "#                         entry #{MARKER_ENTRIES.fetch(m)}: decimal marker U+#{format('%04X', m.ord)}"
    end.join("\n")
  end

  def markers
    @markers ||= @data["decimal_markers"].each do |m|
      abort "decimal marker #{m.inspect} has no entry name" unless MARKER_ENTRIES.key?(m)
      abort "decimal marker #{m.inspect} must be one character" unless m.length == 1
    end
  end

  def rule(name, branches)
    "  #{name} = #{branches.join(' / ')}"
  end

  # arr_to_expression: str(w).as(name) for each word, in array order.
  def named_list(rule_name, words, capture)
    rule(rule_name, words.map { |w| "(#{lit(w)}) as #{capture}" })
  end

  # A PARG literal for an arbitrary string: printable text as "..." with \"
  # and \\ escaped; control characters as %x bytes in a grouped sequence.
  def lit(str)
    abort "empty literal" if str.empty?
    pieces = str.each_char.chunk_while { |a, b| printable?(a) == printable?(b) }.flat_map do |run|
      if printable?(run.first)
        ["\"#{run.join.gsub(/["\\]/) { |c| "\\#{c}" }}\""]
      else
        run.map { |c| hex(c.ord) }
      end
    end
    pieces.size == 1 ? pieces.first : "(#{pieces.join(' ')})"
  end

  # ASCII only: everything else is written as %x code points, so the
  # generated .parg is pure ASCII. (Parsanol 1.3.107's PARG lexer indexes the
  # source by character offset, which is quadratic on a non-ASCII string; with
  # a few hundred KB of source that alone costs ~30 s at every artifact load,
  # because Artifact#root_atom re-lexes the embedded source.)
  def printable?(char)
    char.ord >= 0x20 && char.ord < 0x7F
  end

  def hex(code)
    format("%%x%02X", code)
  end

  # Parse a one-character Ruby regexp class ("[...]" or "[^...]", optionally
  # wrapped in (?-mix:...)) into [negated, [[lo, hi], ...]].
  def parse_class(src)
    src = src.sub(/\A\(\?-mix:(.*)\)\z/m, '\1')
    abort "not a character class: #{src.inspect}" unless src.start_with?("[") && src.end_with?("]")
    body = src[1..-2]
    negated = body.start_with?("^")
    body = body[1..] if negated
    chars = body.chars
    ranges = []
    i = 0
    while i < chars.size
      c = chars[i]
      if c == "\\"
        e = chars[i + 1]
        i += 2
        if e == "s"
          [0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C].each { |x| ranges << [x, x] }
          next
        end
        abort "unsupported escape \\#{e} in #{src.inspect}" unless e =~ /[^A-Za-z0-9]/
        lo = e.ord
      else
        lo = c.ord
        i += 1
      end
      if chars[i] == "-" && i + 1 < chars.size
        hi_c = chars[i + 1]
        abort "escaped range end in #{src.inspect}" if hi_c == "\\"
        ranges << [lo, hi_c.ord]
        i += 2
      else
        ranges << [lo, lo]
      end
    end
    [negated, ranges]
  end

  def class_alt(ranges)
    merged = ranges.sort.each_with_object([]) do |(lo, hi), acc|
      if acc.any? && lo <= acc.last[1] + 1
        acc.last[1] = [acc.last[1], hi].max
      else
        acc << [lo, hi]
      end
    end
    merged.map { |lo, hi| lo == hi ? hex(lo) : "#{hex(lo)}-#{format('%02X', hi)}" }.join(" / ")
  end

  def complement(ranges)
    out = []
    nxt = 0
    ranges.sort.each do |lo, hi|
      out << [nxt, lo - 1] if lo > nxt
      nxt = [nxt, hi + 1].max
    end
    out << [nxt, 0x10FFFF] if nxt <= 0x10FFFF
    out
  end

  def symbol_char
    src = @data["symbol_char_class"]
    negated, ranges = parse_class(src)
    abort "symbol class is expected to be negated" unless negated
    ["  # match(#{src.gsub(/[^\x00-\x7F]/) { |c| format('\\u{%X}', c.ord) }})",
     # The complement as positive ranges: the Parsanol 1.3.107 Ruby engine
     # accepts "ℛ" for `!symbol_char_excluded any_char` (native rejects it).
     "  symbol_char = #{class_alt(complement(ranges))}"].join("\n")
  end

  # read_text: match("[^#{close}]").repeat for the captured open paren.
  def read_text
    arms = []
    lines = ["  # read_text: Constants::PARENTHESIS[captured :paren] => match(\"[^close]\").repeat"]
    @data["parenthesis"].each_with_index do |(open, close), i|
      abort "paren #{close.inspect} is not one character" unless close.length == 1
      lines << "  read_text_#{i} = *(!#{lit(close)} any_char)"
      arms << "(#{lit(open)} (read_text_#{i}) as text)"
    end
    # One branch per PARENTHESIS pair, in lparen order: the open paren's own
    # text is unnamed (dropped from the tree), exactly like lparen.capture.
    lines << "  text_body = #{arms.join(' / ')}"
    lines.join("\n")
  end

  # decimal_marker: str(Plurimath.configuration.decimal), one literal rule
  # per marker; specialise! rewrites the references.
  def decimal_marker
    lines = ["  # decimal_marker: str(Plurimath.configuration.decimal), one rule per marker"]
    markers.each { |m| lines << "  decimal_marker__#{MARKER_ENTRIES.fetch(m)} = #{lit(m)}" }
    lines.join("\n")
  end

  # One entry per decimal marker, then its declared bindings: the single
  # `root` capture bound whole, as plain data, for the typed model.
  def entries
    names = markers.map { |m| MARKER_ENTRIES.fetch(m) }
    (names.map { |name| "entry #{name}: document__#{name}" } +
      [""] +
      names.map { |name| "bindings document__#{name} { root -> expression (any) }" }).join("\n")
  end

  TOKEN = /"(?:[^"\\]|\\.)*"|\bas\s+\w+|%x[0-9A-Fa-f.\-]+|\b[A-Za-z_]\w*\b/

  # Emit every rule that (transitively) references decimal_marker once per
  # marker, suffixed __<entry>, with references rewritten to the same marker.
  def specialise!(text)
    rule_re = /\A  ([A-Za-z_]\w*) = (.*)\z/
    rules = {}
    text.each_line { |l| (m = l.chomp.match(rule_re)) && (rules[m[1]] = m[2]) }
    refs = rules.transform_values do |body|
      body.scan(TOKEN).select { |t| t.match?(/\A[A-Za-z_]\w*\z/) && t != "decimal_marker" ? rules.key?(t) : t == "decimal_marker" }.uniq
    end
    dependent = Set.new
    loop do
      added = refs.select { |r, rs| !dependent.include?(r) && rs.any? { |t| t == "decimal_marker" || dependent.include?(t) } }.keys
      break if added.empty?

      dependent.merge(added)
    end
    abort "expression must depend on decimal_marker" unless dependent.include?("expression")
    text.each_line.map do |line|
      m = line.chomp.match(rule_re)
      next line unless m && dependent.include?(m[1])

      markers.map do |mk|
        sfx = "__#{MARKER_ENTRIES.fetch(mk)}"
        body = m[2].gsub(TOKEN) { |t| t == "decimal_marker" || dependent.include?(t) ? "#{t}#{sfx}" : t }
        "  #{m[1]}#{sfx} = #{body}\n"
      end.join
    end.join
  end

  def base_number_prefix
    @data["base_number_prefix"].map do |name, atom|
      "  #{name} = #{atom_parg(atom)}"
    end.join("\n")
  end

  def atom_parg(atom)
    if atom.key?("seq") then atom["seq"].map { |a| group(atom_parg(a)) }.join(" ")
    elsif atom.key?("alt") then atom["alt"].map { |a| group(atom_parg(a)) }.join(" / ")
    elsif atom.key?("as") then "(#{atom_parg(atom['of'])}) as #{atom['as']}"
    elsif atom.key?("repeat")
      body = "(#{atom_parg(atom['repeat'])})"
      case [atom["min"], atom["max"]]
      when [1, nil] then "1*#{body}"
      when [0, nil] then "*#{body}"
      when [0, 1] then "[#{atom_parg(atom['repeat'])}]"
      else "#{atom['min']}*#{atom['max']}#{body}"
      end
    elsif atom.key?("str") then lit(atom["str"])
    elsif atom.key?("re")
      negated, ranges = parse_class(atom["re"])
      negated ? "!(#{class_alt(ranges)}) any_char" : class_alt(ranges)
    else abort "unknown atom #{atom.inspect}"
    end
  end

  def group(text)
    text.match?(/\A[\w"%]\S*\z/) ? text : "(#{text})"
  end

  # hash_to_expression(Constants.precompile_constants) via dynamic_parser_rules.
  def vocabulary
    underscore = @data["unary_underscore_words"]
    slash_done = false
    slash_word = "\\"
    branches = @data["precompile_constants"].flat_map do |word, category|
      w = lit(word)
      case category
      when "symbol"
        out = slash_done ? [] : [[slash_word, "slash_newline", false]]
        slash_done = true
        out + [[word, "((#{w}) as symbol)", false]]
      when "unary_class"
        if underscore.include?(word)
          [[word, "(((#{w}) as unary_class space_opt (\"_\") as symbol) as unary / ((#{w}) as unary_class space_opt [sequence]) as unary)", true]]
        else
          [[word, "((((#{w}) as unary_class) as power_base space_opt power_base) as unary / ((#{w}) as unary_class space_opt [sequence]) as unary)", true]]
        end
      when "fonts" then [[word, "((#{w}) as fonts_class space_opt (sequence) as fonts_value)", true]]
      when "special_fonts" then [[word, "((#{w}) as bold_fonts)", false]]
      else abort "unknown vocabulary category #{category.inspect} for #{word.inspect}"
      end
    end
    # Every branch starts with its word's literal, so branches whose words
    # start with different characters can never both match at one position:
    # the alternation equals, at any position, its branches for that first
    # character in their original order. Grouping by first character (order
    # kept inside each group) and dispatching through a balanced tree of
    # character-range lookaheads is therefore the same choice, without
    # trying all 3,300 literals at every position (the native engine is slow
    # on a flat alternation this wide). The whole alternation is inlined
    # (parenthesised) where Parslet inlines it.
    @vocab_rules = []
    groups = branches.group_by { |word, _, _| word[0].ord }.sort.map do |cp, list|
      [cp, runs(cp, list)]
    end
    dispatch(groups)
  end

  # Consecutive decimal-independent branches of one first-character group
  # become a shared rule (order kept); dependent branches (unary, fonts)
  # stay inline because they reference sequence / power_base.
  def runs(codepoint, list)
    list.chunk_while { |a, b| a[2] == b[2] }.flat_map do |run|
      if run.first[2] || run.size < 2
        run.map { |b| b[1] }
      else
        name = "vocabulary_#{@vocab_rules.size}"
        @vocab_rules << "  #{name} = &#{hex(codepoint)} (#{run.map { |b| b[1] }.join(' / ')})"
        [name]
      end
    end
  end

  def dispatch(groups)
    if groups.size == 1
      list = groups.first.last
      return list.size == 1 ? list.first : "(#{list.join(' / ')})"
    end

    mid = groups.size / 2
    left = groups[0...mid]
    right = groups[mid..]
    lo = left.first.first
    hi = left.last.first
    guard = lo == hi ? hex(lo) : "#{hex(lo)}-#{format('%02X', hi)}"
    "((&#{guard} #{dispatch(left)}) / #{dispatch(right)})"
  end
end

# Steps 2-4 over the expanded grammar +text+: [grammar, normalizer].
def normalize(text)
  rules = PargRuleTree.read(text)
  norm = AmathShapes.new(rules, catalog: CATALOG).run
  clash = norm.collisions
  abort "normalization leaves wrapper collisions: #{clash.join('; ')}" unless clash.empty?

  rule_re = /\A  ([A-Za-z_]\w*) = (.*)\z/
  out = text.each_line.map do |line|
    m = line.chomp.match(rule_re)
    next line unless m && norm.rules[m[1]] != rules[m[1]]

    "  #{m[1]} = #{PargRuleTree.emit(norm.rules[m[1]])}\n"
  end.join
  abort "the normalized grammar does not read back as the normalized rules" unless PargRuleTree.read(out) == norm.rules

  [out, norm]
end

# grammars/pma.parg.template + the registry's pma entries -> grammars/pma.parg
# (dialect P, plurimath docs/pma.adoc), normalized with the same rules and
# strict checks as dialect L. The header records the registry edition and
# the asciiunits artifact the unit(...) content is parsed with.
class PmaGenerator
  TEMPLATE = File.join(ROOT, "grammars/pma.parg.template")
  # How deep brackets may nest inside unit(...).
  UNIT_DEPTH = 8

  def initialize(registry, registry_bytes, template)
    @registry = registry
    @registry_bytes = registry_bytes
    @template = template
  end

  def generate
    parts = {
      "header" => header,
      "distribution_name" => distribution_name,
      "unit_body" => unit_body,
      "unit_depth" => UNIT_DEPTH.to_s,
    }
    used = []
    out = @template.each_line.filter_map do |line|
      next if line.start_with?("#!")

      line.gsub(/\{\{(\w+)\}\}/) do
        used << ::Regexp.last_match(1)
        parts.fetch(::Regexp.last_match(1)) { abort "unknown placeholder #{::Regexp.last_match(1)}" }
      end
    end.join
    missing = parts.keys - used
    abort "pma placeholders not used by the template: #{missing.join(', ')}" unless missing.empty?
    abort "generated pma grammar is not pure ASCII" unless out.ascii_only?
    reserved_terminals!(out)
    out
  end

  private

  def header
    units = @registry.fetch("units")
    ["# GENERATED by scripts/generate_grammar.rb -- do not edit.",
     "# pma (dialect P) grammar, plurimath docs/pma.adoc (amath#16).",
     "# registry data/vocabulary.json #{@registry['format']} edition #{@registry['edition']} " \
     "sha256:#{Digest::SHA256.hexdigest(@registry_bytes)}",
     "# unit(...) content: #{units['artifact']} #{units['version']} artifact #{units['checksum']}",
     "# reserved words (terminals): #{@registry.fetch('reserved_words').join(' ')}"].join("\n")
  end

  def distribution_name
    names = Registry.entries(@registry, "pma").select { |e| e["category"] == "distribution_names" }.map { |e| e["value"] }
    abort "the registry has no pma distribution names" if names.empty?
    ordered = names.each_with_index.sort_by { |n, i| [-n.length, i] }.map(&:first)
    "  distribution_name = #{ordered.map { |n| %("#{n}") }.join(' / ')}"
  end

  # unit_chunk_<d>: a character, a bracketed group (to depth UNIT_DEPTH)
  # or a whitespace run that stands before more content.
  def unit_body
    (0..UNIT_DEPTH).map do |d|
      group = d < UNIT_DEPTH ? " / \"(\" sp *(unit_chunk_#{d + 1}) sp \")\"" : ""
      lead = d < UNIT_DEPTH ? "unit_char / \"(\"" : "unit_char"
      "  unit_chunk_#{d} = unit_char#{group} / 1*(ws) &(#{lead})"
    end.join("\n")
  end

  # Every reserved word except quantity (which has no production) must
  # start a production as `word(`.
  def reserved_terminals!(text)
    (@registry.fetch("reserved_words") - ["quantity"]).each do |word|
      abort "reserved word #{word} is not a terminal of the pma grammar" unless text.match?(/"#{word}\(?"/)
    end
  end
end

# The pma template writes the captures `literal` and `empty_list` of unit(...)
# itself (a unit with a quantity assertion holds the unit text and the
# quantity in one hash, which normalization cannot build from an unwrapped
# run), so the wrapper-name guard is off for it (normalized: true).
def normalize_pma(text)
  rules = PargRuleTree.read(text)
  norm = AmathShapes.new(rules, normalized: true).run
  clash = norm.collisions
  abort "pma normalization leaves wrapper collisions: #{clash.join('; ')}" unless clash.empty?

  rule_re = /\A  ([A-Za-z_]\w*) = (.*)\z/
  out = text.each_line.map do |line|
    m = line.chomp.match(rule_re)
    next line unless m && norm.rules[m[1]] != rules[m[1]]

    "  #{m[1]} = #{PargRuleTree.emit(norm.rules[m[1]])}\n"
  end.join
  abort "the normalized pma grammar does not read back as the normalized rules" unless PargRuleTree.read(out) == norm.rules

  [out, norm]
end

check = ARGV.delete("--check")
abort "usage: ruby scripts/generate_grammar.rb [--check]" unless ARGV.empty?

registry = Registry.load(VOCAB)
expanded = Generator.new(Registry.legacy_bytes(registry), File.read(TEMPLATE, encoding: "UTF-8")).generate
grammar, norm = normalize(expanded)
captures = norm.rules.values.to_json.scan(/"as":"(\w+)"/).flatten.uniq
Registry.entries(registry, "legacy").map { |e| e["binding"] }.uniq.each do |name|
  missing = registry["bindings"].fetch(name).keys - captures
  abort "binding #{name}: leaf #{missing.join(', ')} is not a capture of the dialect L grammar" unless missing.empty?
end
wrappers = "#{JSON.pretty_generate(
  'format' => 'amath-wrappers/1',
  'wrappers' => norm.wrapper_list,
  'rules' => norm.counts.sort.to_h,
)}\n"
normalized = "#{JSON.generate('format' => NORMALIZED_FORMAT, 'root' => ROOT_RULE, 'rules' => norm.rules)}\n"
outputs = { OUT => grammar, WRAPPERS_OUT => wrappers, NORMALIZED_OUT => normalized }

pma_expanded = PmaGenerator.new(registry, File.binread(VOCAB),
                                File.read(PmaGenerator::TEMPLATE, encoding: "UTF-8")).generate
pma_grammar, pma_norm = normalize_pma(pma_expanded)
pma_captures = pma_norm.rules.values.to_json.scan(/"as":"(\w+)"/).flatten.uniq
Registry.entries(registry, "pma").map { |e| e["binding"] }.uniq.each do |name|
  missing = registry["bindings"].fetch(name).keys - pma_captures
  abort "binding #{name}: leaf #{missing.join(', ')} is not a capture of the pma grammar" unless missing.empty?
end
outputs[File.join(ROOT, "grammars/pma.parg")] = pma_grammar
outputs[File.join(ROOT, "grammars/pma.wrappers.json")] = "#{JSON.pretty_generate(
  'format' => 'amath-wrappers/1',
  'wrappers' => pma_norm.wrapper_list,
  'rules' => pma_norm.counts.sort.to_h,
)}\n"
outputs[File.join(ROOT, "grammars/pma.normalized-rules.json")] =
  "#{JSON.generate('format' => NORMALIZED_FORMAT, 'root' => 'document', 'rules' => pma_norm.rules)}\n"
relative = ->(path) { path.delete_prefix("#{ROOT}/") }
if check
  stale = outputs.reject { |path, text| File.exist?(path) && File.read(path, encoding: "UTF-8") == text }.keys
  if stale.empty?
    puts "#{outputs.keys.map(&relative).join(', ')} up to date"
  else
    warn "stale: #{stale.map(&relative).join(', ')}; run ruby scripts/generate_grammar.rb"
    exit 1
  end
else
  outputs.each do |path, text|
    File.write(path, text)
    puts "wrote #{relative.(path)} bytes=#{text.bytesize} sha256:#{Digest::SHA256.hexdigest(text)}"
  end
end
