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

  it "keeps deep input off the native engine on other threads" do
    input = "#{'(' * 100}x#{')' * 100}"
    tree, engine = Thread.new { [Amath.parse(input), Amath.last_engine] }.value
    expect(tree).to eq(Amath.parse(input, engine: :ruby))
    expect(engine).to eq(:ruby)
  end

  it "rejects deep input for engine: :native on other threads" do
    input = "#{'(' * 100}x#{')' * 100}"
    error = Thread.new do
      Amath.parse(input, engine: :native)
    rescue Amath::NestingTooDeep => e
      e
    end.value
    expect(error).to be_a(Amath::NestingTooDeep)
  end

  it "still parses shallow input natively on other threads" do
    engine = Thread.new { Amath.parse("(x)"); Amath.last_engine }.value
    expect(engine).to eq(:native)
  end

  # Each item of the {expr: item + {expr: ...}} chain of a parsed sum, without
  # its :expr key, with every Slice as [text, offset]. Iterative: the chain is
  # as deep as the sum is long.
  def sum_items(tree)
    items = []
    node = tree
    while node.is_a?(Hash) && node.key?(:expr)
      node = node[:expr]
      items << located(node.is_a?(Hash) ? node.except(:expr) : node)
    end
    items
  end

  def located(tree, shift = 0)
    case tree
    when Hash then tree.transform_values { |v| located(v, shift) }
    when Array then tree.map { |v| located(v, shift) }
    when Parsanol::Slice then [tree.to_s, tree.offset + shift]
    else tree
    end
  end

  # The items of the sum of +count+ +term+s joined by " + ", from the parse
  # of one +term+ shifted to each term's offset.
  def expected_sum_items(term, count, engine)
    one = Amath.parse(term, engine: engine)[:expr]
    step = term.bytesize + 3
    (0...count).flat_map do |i|
      item = located(one, i * step)
      plus = { sequence: { symbol: ["+", (i * step) + term.bytesize + 1] } }
      i == count - 1 ? [item] : [item, plus]
    end
  end

  # Sums and sequences are parsed as repetitions and renested by
  # Amath::Renester, so their length costs no recursion depth on either
  # engine (Plurimath#transform_depth_spec: 750 and 800 terms).
  engines = %i[native ruby]
  [["x", 800], ["x", 2000], ["x", 5000], ["sqrt x", 800]].each do |term, count|
    engines.each do |engine|
      it "parses a sum of #{count} #{term.inspect} terms on engine: #{engine}" do
        input = Array.new(count, term).join(" + ")
        tree = Amath.parse(input, engine: engine)
        expect(Amath.last_engine).to eq(engine)
        expect(sum_items(tree)).to eq(expected_sum_items(term, count, engine))
      end
    end
  end

  it "parses a long sum of matrices and matrix fractions on both engines" do
    terms = ["[[1,2],[3,4]]", "[[1,2],[3,4]]/x"]
    input = Array.new(400) { |i| terms[i % 2] }.join(" + ")
    native, ruby = %i[native ruby].map do |engine|
      leaves(Amath.parse(input, engine: engine)).map { |s| [s.to_s, s.offset] }
    end
    expect(native).to eq(ruby)
    expect(native.last).to eq(["x", input.bytesize - 1])
  end

  it "keeps a long sum on the native engine under :auto" do
    Amath.parse(Array.new(2000, "x").join(" + "))
    expect(Amath.last_engine).to eq(:native)
  end

  it "restores the guard flag after a native call" do
    Amath.parse("#{'(' * 200}x")
    expect(Thread.current[Amath::NativeRecursionGuard::KEY]).to be_nil
  end
end
