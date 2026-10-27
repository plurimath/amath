# frozen_string_literal: true

RSpec.describe Amath::Renester do
  def slice(text, offset)
    Parsanol::Slice.new(offset, text)
  end

  def step(value)
    { amath_step: value }
  end

  # A chain node as the grammar returns it: under its outermost level's key.
  def chain(items, key = :expr)
    { key => { amath_chain: items } }
  end

  it "returns trees without chains unchanged" do
    tree = { expr: [{ symbol: slice("x", 0) }, ""], text: slice("a", 2) }
    expect(described_class.call(tree)).to eq(tree)
    expect(described_class.call("")).to eq("")
  end

  it "nests the steps of a chain, innermost last" do
    x = { sequence: { symbol: slice("x", 0) } }
    plus = { sequence: { symbol: slice("+", 2) } }
    y = { sequence: { symbol: slice("y", 4) } }
    tree = chain([step(x), step(plus), step(y)])
    expect(described_class.call(tree))
      .to eq({ expr: x.merge(expr: plus.merge(expr: y)) })
  end

  it "nests left_right parts as :left_right levels" do
    table = { table: { table_left: slice("[", 0) } }
    y = { symbol: slice("y", 9) }
    tree = chain([{ amath_lr: table }, step(y)], :left_right)
    expect(described_class.call(tree))
      .to eq({ left_right: table.merge(expr: y) })
  end

  it "merges the closing item into the last step" do
    lr = { left_right: { left: slice("(", 9) } }
    under = { symbol: slice("_", 0) }
    tree = chain([step(under), { amath_end: lr }])
    expect(described_class.call(tree)).to eq({ expr: under.merge(lr) })
  end

  it "keeps a text step when the rest is empty, as the parser's merge does" do
    space = slice(" ", 0)
    bare = chain([step(space)])
    closed = chain([step(space), { amath_end: "" }])
    expect(described_class.call(bare)).to eq({ expr: space })
    expect(described_class.call(closed)).to eq({ expr: space })
  end

  it "replaces a text step by a Hash rest" do
    rest = { comma: slice(",", 1) }
    tree = chain([step(slice(" ", 0)), { amath_end: rest }])
    expect(described_class.call(tree)).to eq({ expr: rest })
  end

  it "merges a step with the rest as Parsanol merges sequence results" do
    h = { symbol: slice("x", 0) }
    sl = slice(" ", 1)
    {
      [h, ""] => h, [h, sl] => h, [sl, h] => h, ["", sl] => sl,
      [sl, ""] => sl, ["", ""] => "", [[h], h] => [h, h], [h, [h]] => [h, h]
    }.each do |(part, rest), merged|
      tree = chain([step(part), { amath_end: rest }])
      expect(described_class.call(tree)).to eq({ expr: merged })
    end
  end

  it "keeps the chain's key in place among its siblings" do
    tree = { frac: slice("f", 0) }
      .merge(chain([step({ symbol: slice("x", 3) })]))
      .merge(comma: slice(",", 5))
    out = described_class.call(tree)
    expect(out.keys).to eq(%i[frac expr comma])
  end

  it "keeps two merged chains whose outermost keys differ" do
    table = { table: { table_left: slice("[", 0) } }
    tree = chain([{ amath_lr: table }], :left_right)
      .merge(chain([step({ symbol: slice("b", 2) })]))
    expect(described_class.call(tree)).to eq(
      { left_right: table, expr: { symbol: slice("b", 2) } },
    )
  end

  it "rebuilds chains nested in steps, ends and arrays" do
    inner = chain([step({ symbol: slice("y", 2) })])
    tree = [chain([step({ lparen: slice("(", 1) }.merge(inner)),
                   { amath_end: { left_right: inner } }])]
    expect(described_class.call(tree)).to eq(
      [{ expr: { lparen: slice("(", 1), expr: { symbol: slice("y", 2) },
                 left_right: { expr: { symbol: slice("y", 2) } } } }],
    )
  end

  it "builds a chain of 100,000 steps without recursion" do
    steps = Array.new(100_000) { |i| step({ symbol: slice("x", i) }) }
    tree = chain(steps)
    out = Thread.new { described_class.call(tree) }.value
    depth = 0
    node = out
    while node.is_a?(Hash) && node.key?(:expr)
      depth += 1
      node = node[:expr]
    end
    expect(depth).to eq(100_000)
  end
end
