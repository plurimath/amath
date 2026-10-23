# frozen_string_literal: true

# Input nested deeper than Parsanol's native recursion limit (about 110
# levels of "(" and 80 of "{" with the AsciiMath artifact). Under
# engine: :auto amath reruns such input on the Ruby engine itself, instead of
# letting Parsanol's native error path reparse it through its interpreter
# (which took minutes or raised SystemStackError).
RSpec.describe "Amath deep nesting" do
  before do
    require_native!
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
  end

  # The time limit is for the deep parse itself, not the one-time load of
  # the artifact and its Ruby-engine program, so both are warmed first.
  def timed
    Amath.parse("{x}", engine: :ruby)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  end

  # Every Parsanol::Slice leaf of +tree+, depth-first (iterative: the tree is
  # as deep as the input).
  def leaves(tree)
    out = []
    stack = [tree]
    until stack.empty?
      node = stack.pop
      case node
      when Hash then stack.concat(node.values.reverse)
      when Array then stack.concat(node.reverse)
      when Parsanol::Slice then out << node
      end
    end
    out
  end

  # The tree of "{"*depth + "x" + "}"*depth, built from the one-level shape.
  def braces_tree(depth)
    inner = { expr: { sequence: { symbol: "x" } } }
    depth.times do
      inner = { expr: { sequence: { intermediate_exp: {
        lparen: "{", expr: inner, rparen: "}"
      } } } }
    end
    inner
  end

  # The tree with every Slice replaced by its String.
  def plain(tree)
    case tree
    when Hash then tree.transform_values { |v| plain(v) }
    when Array then tree.map { |v| plain(v) }
    when Parsanol::Slice then tree.to_s
    else tree
    end
  end

  it "installs the recursion-limit guard into Parsanol's native error path" do
    expect(Amath::NativeRecursionGuard.installed?).to be(true)
  end

  it "builds the same shallow brace tree as the parser" do
    expect(plain(Amath.parse("{{x}}"))).to eq(braces_tree(2))
  end

  it "parses 200 levels of braces under :auto on the Ruby engine" do
    input = "#{'{' * 200}x#{'}' * 200}"
    tree, seconds = timed { Amath.parse(input) }
    expect(Amath.last_engine).to eq(:ruby)
    expect(seconds).to be < 10
    expect(plain(tree)).to eq(braces_tree(200))
  end

  it "parses 200 levels of parentheses under :auto like the Ruby engine" do
    input = "#{'(' * 200}x#{')' * 200}"
    tree, seconds = timed { Amath.parse(input) }
    expect(Amath.last_engine).to eq(:ruby)
    expect(seconds).to be < 10
    expect(tree).to eq(Amath.parse(input, engine: :ruby))
    expect(leaves(tree).map(&:to_s).join.count("(")).to eq(200)
    expect(leaves(tree).find { |s| s.to_s == "x" }.offset).to eq(200)
  end

  it "parses 200 unclosed parentheses under :auto" do
    _, seconds = timed { Amath.parse("#{'(' * 200}x") }
    expect(Amath.last_engine).to eq(:ruby)
    expect(seconds).to be < 10
  end

  it "keeps the native engine for input within its limit" do
    input = "#{'(' * 50}x#{')' * 50}"
    tree = Amath.parse(input)
    expect(Amath.last_engine).to eq(:native)
    expect(tree).to eq(Amath.parse(input, engine: :ruby))
  end

  it "raises NestingTooDeep under engine: :native instead of running Ruby" do
    allow(Amath.artifact).to receive(:parse).and_call_original
    expect { Amath.parse("#{'{' * 200}x#{'}' * 200}", engine: :native) }
      .to raise_error(Amath::NestingTooDeep, /native engine's recursion limit.*engine: :ruby/) { |e|
        expect(e).to be_a(Amath::ParseError)
        expect(e.byte_offset).to be_nil
        expect(e.char_offset).to be_nil
      }
    expect(Amath.last_engine).to eq(:native)
    expect(Amath.artifact).not_to have_received(:parse).with(anything, anything, mode: :ruby)
  end

  it "never lets SystemStackError escape on deep rejected input" do
    input = "#{'(' * 1000}a/#{')' * 1000}"
    %i[auto ruby].each do |engine|
      expect { Amath.parse(input, engine: engine) }.to raise_error(Amath::ParseError)
      expect(Amath.last_engine).to eq(:ruby)
    end
  end

  it "falls back to Ruby on a thread whose stack the native call exhausts" do
    input = "#{'(' * 100}x#{')' * 100}"
    tree, engine = Thread.new { [Amath.parse(input), Amath.last_engine] }.value
    expect(tree).to eq(Amath.parse(input, engine: :ruby))
    expect(engine).to eq(:native).or eq(:ruby)
  end

  it "restores the guard flag after a native call" do
    Amath.parse("#{'(' * 200}x")
    expect(Thread.current[Amath::NativeRecursionGuard::KEY]).to be_nil
  end
end
