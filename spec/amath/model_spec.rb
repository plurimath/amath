# frozen_string_literal: true

require "yaml"

# Amath.parse_model returns the typed model (Amath::Model::Document), built by
# lutaml-model from the declared binding of the bundled artifact.
RSpec.describe "Amath.parse_model typed model" do
  before(:all) do
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
    @artifact = Amath.artifact
    @bindings = Amath.bindings
  end

  before do
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
    allow(Amath).to receive_messages(artifact: @artifact, bindings: @bindings)
  end

  def items(document)
    document.expression.expr.amath_chain
  end

  %i[native ruby].each do |engine|
    context "with engine: #{engine.inspect}" do
      before { require_native! if engine == :native }

      it "returns a Document holding the expression and the decimal marker" do
        doc = Amath.parse_model("x", engine: engine)
        expect(doc).to be_an_instance_of(Amath::Model::Document)
        expect(doc.decimal).to eq(".")
        expect(doc.expression).to be_an_instance_of(Amath::Model::Expression)
        expect(Amath.last_engine).to eq(engine)
      end

      it "returns an empty Document for empty input" do
        doc = Amath.parse_model("", engine: engine)
        expect(doc).to be_an_instance_of(Amath::Model::Document)
        expect(doc.expression).to be_nil
      end

      it "keeps a flat expression chain as a list of items" do
        list = items(Amath.parse_model("a+b", engine: engine))
        expect(list.map(&:class).uniq).to eq([Amath::Model::AmathChainItem])
        expect(list.filter_map { |i| i.amath_step&.sequence&.symbol&.spelling }).to eq(%w[a + b])
        expect(list.last.amath_end).to be_an_instance_of(Amath::Model::AmathEnd)
      end

      it "types catalog text as MathSymbol with its Unicode value and kind" do
        list = items(Amath.parse_model("alpha -> (x)", engine: engine))
        alpha = list.first.amath_step.sequence.symbol
        expect(alpha).to be_an_instance_of(Amath::Model::MathSymbol)
        expect([alpha.spelling, alpha.value, alpha.kind]).to eq(%w[alpha α symbol])
        arrow = list[1].amath_step.sequence.symbol
        expect([arrow.spelling, arrow.value]).to eq(%w[-> →])
        paren = list[2].amath_step.sequence.intermediate_exp
        expect([paren.lparen.value, paren.lparen.kind]).to eq(%w[( open])
        expect([paren.rparen.value, paren.rparen.kind]).to eq(%w[) close])
      end

      it "keeps an unlisted symbol as its own text" do
        symbol = items(Amath.parse_model("x", engine: engine)).first.amath_step.sequence.symbol
        expect([symbol.spelling, symbol.value, symbol.kind]).to eq(%w[x x unlisted])
      end

      {
        "." => "1.5",
        "," => "1,5",
        "٫" => "1٫5",
      }.each do |marker, input|
        it "keeps the number #{input.inspect} as written under decimal: #{marker.inspect}" do
          doc = Amath.parse_model(input, decimal: marker, engine: engine)
          expect(doc.decimal).to eq(marker)
          expect(items(doc).first.amath_step.sequence.number).to eq(input)
        end
      end

      it "types a shared-exponent uncertainty form" do
        u = items(Amath.parse_model('uexp((1.50, 0.20)e-3, 2, 0.95, "unitsml(m)")', engine: engine))
            .first.amath_step.sequence.uncertainty
        expect(u).to be_an_instance_of(Amath::Model::Uncertainty)
        expect([u.uncertainty_class, u.value, u.magnitude, u.shared_exponent,
                u.coverage_factor, u.coverage_probability, u.unit.literal])
          .to eq(["uexp", "1.50", "0.20", "-3", "2", "0.95", "m"])
      end

      it "types ucov with its interval kind" do
        u = items(Amath.parse_model("ucov(5, 4, 6, 0.9, shortest)", engine: engine))
            .first.amath_step.sequence.uncertainty
        expect([u.uncertainty_class, u.value, u.lower, u.upper, u.coverage_probability, u.interval_kind])
          .to eq(%w[ucov 5 4 6 0.9 shortest])
      end

      it "raises ParseError with byte and character positions" do
        expect { Amath.parse_model("αβ /", engine: engine) }
          .to raise_error(Amath::ParseError) { |e| expect([e.char_offset, e.byte_offset]).to eq([3, 5]) }
      end
    end
  end

  # 2999 "+" and 3000 terms are 5999 chain steps, then the chain's end.
  it "builds a 3000-term sum as one flat list" do
    input = (["x"] * 3000).join("+")
    list = items(Amath.parse_model(input))
    expect(list.size).to eq(6000)
    expect(list[-2].amath_step.sequence.symbol.spelling).to eq("x")
  end

  it "types every corpus uncertainty case with its source texts" do
    corpus = YAML.safe_load_file(File.expand_path("../../corpora/uncertainty-shared-exponent.yml", __dir__))
    corpus.fetch("cases").each do |c|
      u = items(Amath.parse_model(c.fetch("input"))).first.amath_step.sequence.uncertainty
      # A unit is a text run (rule N8): its text is unit.literal.
      got = c.fetch("tree").to_h { |k, _| [k, k == "unit" ? u.unit.literal : u.public_send(k)] }
      expect(got).to eq(c.fetch("tree").transform_values(&:to_s))
    end
  end

  it "rebuilds the legacy tree of every corpus case from the raw tree" do
    corpus = YAML.safe_load_file(File.expand_path("../../corpora/uncertainty-shared-exponent.yml", __dir__))
    corpus.fetch("cases").each do |c|
      tree = Amath::Parser.raw(c.fetch("input"), engine: :ruby)
      leaf = tree.dig(:expr, :sequence, :uncertainty)
      expect(leaf.transform_keys(&:to_s).transform_values(&:to_s)).to eq(c.fetch("tree").transform_values(&:to_s))
    end
  end

  it "exports every model class as LML" do
    path = File.expand_path("../../model/asciimath.lml.json", __dir__)
    models = JSON.parse(File.read(path)).fetch("models")
    expect(models.size).to eq(Amath::Model.classes.size)
  end
end
