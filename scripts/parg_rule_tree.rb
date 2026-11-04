# frozen_string_literal: true

require "parsanol"
require "parsanol/parg"

# PARG rules <-> the rule tree scripts/normalize_shapes.rb works on.
#
# amath writes its grammar as PARG (grammars/asciimath.parg.template), not
# as an export of the legacy Parslet rules. To run the shared shape
# normalization over it, the generator reads the expanded PARG text with
# Parsanol's own PARG parser and turns each rule into the rule-tree form
# the normalizer reads (the form of unicodemath's grammar export):
#
#   "x"            {"str" => "x"}
#   %x30-39        {"re" => [[0x30, 0x39]]}         one character class
#   a b            {"seq" => [a, b]}
#   a / b          {"alt" => [a, b]}
#   m*n(x)         {"rep" => x, "min" => m, "max" => n}   (n nil: unbounded)
#   [x]            {"rep" => x, "min" => 0, "max" => 1, "tag" => "maybe"}
#   &x / !x        {"look" => x, "positive" => true / false}
#   (x) as name    {"as" => name, "of" => x}
#   name           {"ref" => name}
#
# PargRuleTree.emit writes a rule tree back as PARG text. Reading the
# emitted text gives the same tree (the generator checks this for every
# rule it rewrites), so the normalized grammar is exactly the normalized
# rule tree.
module PargRuleTree
  module_function

  # name => rule tree, for every rule of the PARG +text+, in source order.
  def read(text)
    document = Parsanol::PARG::Parser.new(text).parse
    document.rules.transform_values { |node| tree(node) }
  end

  def tree(node)
    case node.kind
    when :lit
      raise ArgumentError, "case-folded literal #{node.a.inspect}" if node.b

      { "str" => node.a }
    when :class then { "re" => node.a.map(&:dup) }
    when :seq then { "seq" => node.a.map { |n| tree(n) } }
    when :alt then { "alt" => node.a.map { |n| tree(n) } }
    when :rep then { "rep" => tree(node.a), "min" => node.b, "max" => node.c }
    when :opt then { "rep" => tree(node.a), "min" => 0, "max" => 1, "tag" => "maybe" }
    when :pred
      raise ArgumentError, "lookbehind is not supported" if node.c

      { "look" => tree(node.b), "positive" => node.a }
    when :cap then { "as" => node.a, "of" => tree(node.b) }
    when :ref then { "ref" => node.a }
    else raise ArgumentError, "unsupported PARG node #{node.kind.inspect}"
    end
  end

  # PARG text of a rule tree. Every compound operand is parenthesised, so
  # the text reads back as the same tree.
  def emit(node)
    case node.keys.first
    when "str" then literal(node["str"])
    when "re" then node["re"].map { |lo, hi| lo == hi ? hex(lo) : "#{hex(lo)}-#{format('%02X', hi)}" }.join(" / ").then { |t| node["re"].size > 1 ? "(#{t})" : t }
    when "seq" then node["seq"].map { |c| operand(c) }.join(" ")
    when "alt" then node["alt"].map { |c| c.key?("alt") ? "(#{emit(c)})" : emit(c) }.join(" / ")
    when "rep" then repetition(node)
    when "look" then "#{node['positive'] ? '&' : '!'}(#{emit(node['look'])})"
    when "as"
      return "\"\" as #{node['as']}" if node["of"] == { "str" => "" }

      "(#{emit(node['of'])}) as #{node['as']}"
    when "ref" then node["ref"]
    else raise ArgumentError, "unknown rule-tree node #{node.keys.first.inspect}"
    end
  end

  def repetition(node)
    return "[#{emit(node['rep'])}]" if node["tag"] == "maybe"

    min = node["min"]
    max = node["max"]
    prefix = if max.nil? then min.zero? ? "*" : "#{min}*"
             elsif min == max then min.to_s
             else "#{min}*#{max}"
             end
    "#{prefix}(#{emit(node['rep'])})"
  end

  def operand(node)
    text = emit(node)
    %w[seq alt].include?(node.keys.first) || (node.key?("re") && node["re"].size > 1) ? "(#{text})" : text
  end

  ESCAPES = { "\n" => "\\n", "\t" => "\\t", "\r" => "\\r", "\"" => "\\\"", "\\" => "\\\\" }.freeze

  # A literal as "...": printable ASCII, with the escapes PARG reads
  # (\n \t \r \" \\).
  def literal(str)
    unless str.each_char.all? { |c| ESCAPES.key?(c) || (c.ord >= 0x20 && c.ord < 0x7F) }
      raise ArgumentError, "literal #{str.inspect} is not printable ASCII"
    end

    "\"#{str.gsub(/[\n\t\r"\\]/, ESCAPES)}\""
  end

  def hex(code)
    format("%%x%02X", code)
  end
end
