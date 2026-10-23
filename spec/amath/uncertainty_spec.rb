# frozen_string_literal: true

require "spec_helper"
require "yaml"

# AsciiMath measurement-uncertainty syntax (plurimath#493): ustd(...),
# uexp(...) and ucov(...). The trees are the contract in Plurimath's
# docs/uncertainty-asciimath-tree.md: {expr: {sequence: {uncertainty: {...}}}}
# with bare text leaves.
module UncertaintyTrees
  ARTIFACT = File.expand_path("../../artifacts/asciimath.json", __dir__)

  # Plurimath's acceptance contract; every AsciiMath input cell is parsed.
  CONTRACT_PATH = ENV.fetch(
    "PLURIMATH_UNCERTAINTY_CONTRACT",
    File.expand_path("../fixtures/uncertainty_contract.yml", __dir__),
  )

  # contract cell id => the tree under `uncertainty:` (:fallback: not a
  # well-formed uncertainty form, so it parses exactly as in FALLBACK;
  # :plain: an ordinary input that never produces this tree).
  TREES = {
    "standard.default" =>
      { uncertainty_class: "ustd", value: "1.230", magnitude: "0.004" },
    "expanded.k_only" =>
      { uncertainty_class: "uexp", value: "10.0", magnitude: "0.3",
        coverage_factor: "2" },
    "expanded.k_and_p" =>
      { uncertainty_class: "uexp", value: "100.02147", magnitude: "0.00079",
        coverage_factor: "2", coverage_probability: "0.95" },
    "asymmetric.shortest_interval" =>
      { uncertainty_class: "ucov", value: "1.024", lower: "0.983",
        upper: "1.088", coverage_probability: "0.95",
        interval_kind: "shortest" },
    "concise_digits.two_places" =>
      { uncertainty_class: "ustd", value: "1.23", concise_digits: "4" },
    "concise_digits.three_places" =>
      { uncertainty_class: "ustd", value: "1.230", concise_digits: "4" },
    "concise_digits.gum_mass" =>
      { uncertainty_class: "ustd", value: "100.02147", concise_digits: "35" },
    "absolute_parentheses.plan" =>
      { uncertainty_class: "ustd", value: "1.23", magnitude: "0.04" },
    "absolute_parentheses.gum_mass" =>
      { uncertainty_class: "ustd", value: "100.02147", magnitude: "0.00035" },
    "units.expanded_gram" =>
      { uncertainty_class: "uexp", value: "100.02147", magnitude: "0.00079",
        coverage_factor: "2", unit: "g" },
    "invalid.asciimath_missing_k" => :fallback,
    "ordinary_pm.numbers" => :plain,
    "ordinary_pm.concise_lookalike" => :plain,
  }.freeze

  # Forms the contract does not cover, built from the tree document.
  EXTRA = {
    "ustd(-1.5, 0.2)" =>
      { uncertainty_class: "ustd", value: "-1.5", magnitude: "0.2" },
    "ustd(1.230(4), \"unitsml(kg)\")" =>
      { uncertainty_class: "ustd", value: "1.230", concise_digits: "4",
        unit: "kg" },
    "uexp(10.0, 0.3, 2, 0.95, \"unitsml(m)\")" =>
      { uncertainty_class: "uexp", value: "10.0", magnitude: "0.3",
        coverage_factor: "2", coverage_probability: "0.95", unit: "m" },
    "ucov(1.024, 0.983, 1.088, 0.95)" =>
      { uncertainty_class: "ucov", value: "1.024", lower: "0.983",
        upper: "1.088", coverage_probability: "0.95" },
    "ucov(1.024, 0.983, 1.088, 0.95, symmetric, \"unitsml(g)\")" =>
      { uncertainty_class: "ucov", value: "1.024", lower: "0.983",
        upper: "1.088", coverage_probability: "0.95",
        interval_kind: "symmetric", unit: "g" },
  }.freeze

  # A ustd/uexp/ucov call that is not a well-formed uncertainty form is not
  # rejected: it falls back to letters, `u exp(...)` / `u s t d(...)`, as in
  # Plurimath's Parslet parser. Trees from the artifact at 2aa5ee2 (before
  # the uncertainty syntax), each leaf as [text, offset]. This includes the
  # contract's invalid.asciimath_missing_k cell, uexp(10.0, 0.3).
  FALLBACK = {
    "uexp(x)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1], intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {symbol: ["x", 5]}}}, rparen: [")", 6]}}}}}},
    "uexp(-t/tau)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1], intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {symbol: ["-", 5]}, expr: {frac: {numerator: {symbol: ["t", 6]}, denominator: {sequence: {symbol: ["tau", 8]}}}}}}, rparen: [")", 11]}}}}}},
    "f = uexp(i omega t)" => {expr: {sequence: {symbol: ["f", 0]}, expr: {sequence: {symbol: ["=", 2]}, expr: {sequence: {symbol: ["u", 4]}, expr: {sequence: {unary: {unary_class: ["exp", 5], intermediate_exp: {lparen: ["(", 8], expr: {expr: {sequence: {symbol: ["i", 9]}, expr: {sequence: {symbol: ["omega", 11]}, expr: {sequence: {symbol: ["t", 17]}}}}}, rparen: [")", 18]}}}}}}}},
    "uexp(2)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1], intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["2", 5]}}}, rparen: [")", 6]}}}}}},
    "ucov(x, y)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["c", 1]}, expr: {sequence: {symbol: ["o", 2]}, expr: {sequence: {symbol: ["v", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {symbol: ["x", 5]}, expr: {comma: [", ", 6], expr: {sequence: {symbol: ["y", 8]}}}}}, rparen: [")", 9]}}}}}}}},
    "ustd" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["s", 1]}, expr: {sequence: {symbol: ["t", 2]}, expr: {sequence: {symbol: ["d", 3]}}}}}},
    "ucov" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["c", 1]}, expr: {sequence: {symbol: ["o", 2]}, expr: {sequence: {symbol: ["v", 3]}}}}}},
    "ustd(x)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["s", 1]}, expr: {sequence: {symbol: ["t", 2]}, expr: {sequence: {symbol: ["d", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {symbol: ["x", 5]}}}, rparen: [")", 6]}}}}}}}},
    "uexp(10.0, 0.3)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1], intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["10.0", 5]}, expr: {comma: [", ", 9], expr: {sequence: {number: ["0.3", 11]}}}}}, rparen: [")", 14]}}}}}},
    "ustd(1.230)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["s", 1]}, expr: {sequence: {symbol: ["t", 2]}, expr: {sequence: {symbol: ["d", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["1.230", 5]}}}, rparen: [")", 10]}}}}}}}},
    "ustd(1.230, 0.004, 2)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["s", 1]}, expr: {sequence: {symbol: ["t", 2]}, expr: {sequence: {symbol: ["d", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["1.230", 5]}, expr: {comma: [", ", 10], expr: {sequence: {number: ["0.004", 12]}, expr: {comma: [", ", 17], expr: {sequence: {number: ["2", 19]}}}}}}}, rparen: [")", 20]}}}}}}}},
    "ucov(1.024, 0.983, 1.088)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["c", 1]}, expr: {sequence: {symbol: ["o", 2]}, expr: {sequence: {symbol: ["v", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["1.024", 5]}, expr: {comma: [", ", 10], expr: {sequence: {number: ["0.983", 12]}, expr: {comma: [", ", 17], expr: {sequence: {number: ["1.088", 19]}}}}}}}, rparen: [")", 24]}}}}}}}},
    "ucov(1.024, 0.983, 1.088, 0.95, probabilistically-symmetric)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["c", 1]}, expr: {sequence: {symbol: ["o", 2]}, expr: {sequence: {symbol: ["v", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["1.024", 5]}, expr: {comma: [", ", 10], expr: {sequence: {number: ["0.983", 12]}, expr: {comma: [", ", 17], expr: {sequence: {number: ["1.088", 19]}, expr: {comma: [", ", 24], expr: {sequence: {number: ["0.95", 26]}, expr: {comma: [", ", 30], expr: {sequence: {symbol: ["p", 32]}, expr: {sequence: {symbol: ["r", 33]}, expr: {sequence: {symbol: ["o", 34]}, expr: {sequence: {symbol: ["b", 35]}, expr: {sequence: {symbol: ["a", 36]}, expr: {sequence: {symbol: ["b", 37]}, expr: {sequence: {symbol: ["i", 38]}, expr: {sequence: {symbol: ["l", 39]}, expr: {sequence: {symbol: ["i", 40]}, expr: {sequence: {symbol: ["s", 41]}, expr: {sequence: {symbol: ["t", 42]}, expr: {sequence: {symbol: ["i", 43]}, expr: {sequence: {symbol: ["c", 44]}, expr: {sequence: {symbol: ["a", 45]}, expr: {sequence: {symbol: ["ll", 46]}, expr: {sequence: {symbol: ["y", 48]}, expr: {sequence: {symbol: ["-", 49]}, expr: {sequence: {symbol: ["s", 50]}, expr: {sequence: {symbol: ["y", 51]}, expr: {sequence: {symbol: ["m", 52]}, expr: {sequence: {symbol: ["m", 53]}, expr: {sequence: {symbol: ["e", 54]}, expr: {sequence: {symbol: ["t", 55]}, expr: {sequence: {symbol: ["r", 56]}, expr: {sequence: {symbol: ["i", 57]}, expr: {sequence: {symbol: ["c", 58]}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}, rparen: [")", 59]}}}}}}}},
    "uexp(10.0, -0.3, 2)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1], intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {number: ["10.0", 5]}, expr: {comma: [", ", 9], expr: {sequence: {symbol: ["-", 11]}, expr: {sequence: {number: ["0.3", 12]}, expr: {comma: [", ", 15], expr: {sequence: {number: ["2", 17]}}}}}}}}, rparen: [")", 18]}}}}}},
  }.freeze

  # Trees from the artifact at 4c5e331 (before this grammar change), with
  # each leaf as [text, offset]. These inputs must parse exactly as before.
  UNCHANGED = {
    "u(x)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 1], expr: {expr: {sequence: {symbol: ["x", 2]}}}, rparen: [")", 3]}}}}},
    "exp(x)" => {expr: {sequence: {unary: {unary_class: ["exp", 0], intermediate_exp: {lparen: ["(", 3], expr: {expr: {sequence: {symbol: ["x", 4]}}}, rparen: [")", 5]}}}}},
    "u exp(x)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 2], intermediate_exp: {lparen: ["(", 5], expr: {expr: {sequence: {symbol: ["x", 6]}}}, rparen: [")", 7]}}}}}},
    "uexp" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1]}}}}},
    "uexp x" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {unary: {unary_class: ["exp", 1], symbol: ["x", 5]}}}}},
    "ustd (1, 2)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["s", 1]}, expr: {sequence: {symbol: ["t", 2]}, expr: {sequence: {symbol: ["d", 3]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 5], expr: {expr: {sequence: {comma_separated: [{number: ["1", 6], comma: [",", 7]}]}, expr: {sequence: {number: ["2", 9]}}}}, rparen: [")", 10]}}}}}}}},
    "us(1, 2)" => {expr: {sequence: {symbol: ["u", 0]}, expr: {sequence: {symbol: ["s", 1]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 2], expr: {expr: {sequence: {comma_separated: [{number: ["1", 3], comma: [",", 4]}]}, expr: {sequence: {number: ["2", 6]}}}}, rparen: [")", 7]}}}}}},
    "1.23 +- 0.04" => {expr: {sequence: {number: ["1.23", 0]}, expr: {sequence: {symbol: ["+-", 5]}, expr: {sequence: {number: ["0.04", 8]}}}}},
    "1.230(4)" => {expr: {sequence: {number: ["1.230", 0]}, expr: {sequence: {intermediate_exp: {lparen: ["(", 5], expr: {expr: {sequence: {number: ["4", 6]}}}, rparen: [")", 7]}}}}},
    "x pm y" => {expr: {sequence: {symbol: ["x", 0]}, expr: {sequence: {symbol: ["pm", 2]}, expr: {sequence: {symbol: ["y", 5]}}}}},
    "a ± b" => {expr: {sequence: {symbol: ["a", 0]}, expr: {sequence: {symbol: ["±", 2]}, expr: {sequence: {symbol: ["b", 5]}}}}},
    "uu x" => {expr: {sequence: {symbol: ["uu", 0]}, expr: {sequence: {symbol: ["x", 3]}}}},
    "ul(x)" => {expr: {sequence: {unary: {unary_class: ["ul", 0], intermediate_exp: {lparen: ["(", 2], expr: {expr: {sequence: {symbol: ["x", 3]}}}, rparen: [")", 4]}}}}},
    "ubrace(x)" => {expr: {sequence: {unary: {unary_class: ["ubrace", 0], intermediate_exp: {lparen: ["(", 6], expr: {expr: {sequence: {symbol: ["x", 7]}}}, rparen: [")", 8]}}}}},
    "sum_(i=1)^n u_i" => {expr: {ternary: {ternary_class: ["sum", 0], base_value: {intermediate_exp: {lparen: ["(", 4], expr: {expr: {sequence: {symbol: ["i", 5]}, expr: {sequence: {symbol: ["=", 6]}, expr: {sequence: {number: ["1", 7]}}}}}, rparen: [")", 8]}}, power_value: {symbol: ["n", 10]}, third_value: {power_base: {power_base: {symbol: ["u", 12]}, base: {base_value: {symbol: ["i", 14]}}}}}}},
    "u_exp(x)" => {expr: {power_base: {power_base: {symbol: ["u", 0]}, base: {base_value: {unary: {unary_class: ["exp", 2], intermediate_exp: {lparen: ["(", 5], expr: {expr: {sequence: {symbol: ["x", 6]}}}, rparen: [")", 7]}}}}}}},
  }.freeze

  def self.plain(tree)
    case tree
    when Hash then tree.to_h { |k, v| [k, plain(v)] }
    when Array then tree.map { |v| plain(v) }
    when String then tree
    else [tree.to_s, tree.offset]
    end
  end

  # Leaves as text only, for comparison with the documented trees.
  def self.texts(tree)
    case tree
    when Hash then tree.to_h { |k, v| [k, texts(v)] }
    when Array then tree.map { |v| texts(v) }
    else tree.to_s
    end
  end

  def self.cells
    YAML.safe_load_file(CONTRACT_PATH)["cases"]
      .flat_map { |c| c["examples"] || [] }
      .select { |e| e.dig("inputs", "asciimath") }
  end
end

RSpec.describe "AsciiMath uncertainty syntax" do
  # spec_helper points Amath at the spike artifact before every example, and
  # each artifact_path= drops the loaded artifact; the first parse with a
  # freshly loaded artifact of this size is slow (tens of seconds), so the
  # artifact is loaded once and handed to Amath for every example.
  before(:all) do
    Amath.artifact_path = UncertaintyTrees::ARTIFACT
    @loaded = Amath.artifact
  end

  before do
    Amath.artifact_path = UncertaintyTrees::ARTIFACT
    allow(Amath).to receive(:artifact).and_return(@loaded)
  end

  it "has an expectation for every AsciiMath cell in the contract" do
    ids = UncertaintyTrees.cells.map { |e| e["id"] }
    expect(ids).to match_array(UncertaintyTrees::TREES.keys)
  end

  %i[native ruby].each do |engine|
    context "with engine: #{engine}" do
      before { require_native! if engine == :native }

      def parse(input, engine)
        Amath.parse(input, engine: engine).tap do
          expect(Amath.last_engine).to eq(engine)
        end
      end

      UncertaintyTrees.cells.each do |cell|
        input = cell.dig("inputs", "asciimath")
        expected = UncertaintyTrees::TREES.fetch(cell["id"])

        it "#{cell['id']}: #{input}" do
          case expected
          when :fallback
            expect(UncertaintyTrees.plain(parse(input, engine)))
              .to eq(UncertaintyTrees::FALLBACK.fetch(input))
          when :plain
            tree = parse(input, engine)
            expect(tree.inspect).not_to include("uncertainty")
          else
            tree = parse(input, engine)
            expect(UncertaintyTrees.texts(tree))
              .to eq(expr: { sequence: { uncertainty: expected } })
            leaves = tree[:expr][:sequence][:uncertainty].values
            expect(leaves).to all(be_a(Parsanol::Slice))
          end
        end
      end

      UncertaintyTrees::EXTRA.each do |input, expected|
        it "parses #{input}" do
          expect(UncertaintyTrees.texts(parse(input, engine)))
            .to eq(expr: { sequence: { uncertainty: expected } })
        end
      end

      it "places the node where any other operand sits" do
        tree = UncertaintyTrees.texts(parse("m = ustd(1.23, 0.04)", engine))
        expect(tree.dig(:expr, :expr, :expr, :sequence, :uncertainty))
          .to eq(uncertainty_class: "ustd", value: "1.23", magnitude: "0.04")
      end

      UncertaintyTrees::FALLBACK.each do |input, before|
        it "falls back to the old tree for #{input}" do
          expect(UncertaintyTrees.plain(parse(input, engine))).to eq(before)
        end
      end

      UncertaintyTrees::UNCHANGED.each do |input, before|
        it "leaves the tree of #{input} unchanged" do
          expect(UncertaintyTrees.plain(parse(input, engine))).to eq(before)
        end
      end
    end
  end
end
