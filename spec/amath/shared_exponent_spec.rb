# frozen_string_literal: true

require "yaml"

RSpec.describe "Shared-exponent uncertainty syntax" do
  artifact = File.expand_path("../../artifacts/asciimath.json", __dir__)
  corpus = YAML.safe_load_file(
    File.expand_path("../../corpora/uncertainty-shared-exponent.yml", __dir__),
  )

  before(:all) do
    Amath.artifact_path = artifact
    @loaded_shared_exponent_artifact = Amath.artifact
  end

  before do
    Amath.artifact_path = artifact
    allow(Amath).to receive(:artifact).and_return(@loaded_shared_exponent_artifact)
  end

  def texts(value)
    case value
    when Hash then value.to_h { |key, child| [key.to_s, texts(child)] }
    when Array then value.map { |child| texts(child) }
    else value.to_s
    end
  end

  def uncertainty_nodes(value)
    case value
    when Hash
      value.filter_map do |key, child|
        child if key == :uncertainty
      end + value.values.flat_map { |child| uncertainty_nodes(child) }
    when Array then value.flat_map { |child| uncertainty_nodes(child) }
    else []
    end
  end

  %i[native ruby].each do |engine|
    context "with #{engine}" do
      before { require_native! if engine == :native }

      corpus.fetch("cases").each do |entry|
        it "preserves the exponent and measured source text for #{entry.fetch('id')}" do
          input = entry.fetch("input")
          tree = Amath.parse(input, engine: engine)

          expect(Amath.last_engine).to eq(engine)
          expect(texts(tree)).to eq(
            "expr" => { "sequence" => { "uncertainty" => entry.fetch("tree") } },
          )
          uncertainty_nodes(tree).fetch(0).each_value do |leaf|
            expect(leaf).to be_a(Parsanol::Slice)
            expect(input.byteslice(leaf.offset, leaf.to_s.bytesize)).to eq(leaf.to_s)
          end
        end
      end

      it "keeps uncertainty decimals independent of the selected ordinary-number marker" do
        [",", "٫"].each do |marker|
          node = uncertainty_nodes(
            Amath.parse("ustd((3.85, 0.23)e4)", decimal: marker, engine: engine),
          ).fetch(0)

          expect(texts(node)).to eq(
            "uncertainty_class" => "ustd", "value" => "3.85",
            "magnitude" => "0.23", "shared_exponent" => "4",
          )
          expect(Amath.last_engine).to eq(engine)
        end
      end

      it "retains byte offsets after multibyte text and trailing operands" do
        input = 'text(é) + ustd((-3.850, 0.230)e+4) / x'
        tree = Amath.parse(input, engine: engine)
        node = uncertainty_nodes(tree).fetch(0)

        expect(texts(node)).to eq(
          "uncertainty_class" => "ustd", "value" => "-3.850",
          "magnitude" => "0.230", "shared_exponent" => "+4",
        )
        expect(node.fetch(:shared_exponent).offset).to eq(input.b.index("+4"))
        node.each_value do |leaf|
          expect(input.byteslice(leaf.offset, leaf.to_s.bytesize)).to eq(leaf.to_s)
        end
        expect(texts(tree).inspect).to include('"x"')
      end

      [
        "ustd((3.85, 0.23) e4)", "ustd((3.85, 0.23)e)",
        "ustd((3.85, 0.23)e+)", "ustd((3.85, 0.23)e-)",
        "ustd((3.85, 0.23)e- 3)", "ustd((3.85, 0.23)e1.5)",
        "ustd((3.85, 0.23)E4)", "ustd((3.85, 0.23)e4x)",
        "ustd((+3.85, 0.23)e4)", "ustd((3.85, -0.23)e4)",
        "ustd(680(41) e-3)", "ustd(680(41)e-)",
        "uexp((3.85, -0.23)e4, 2)",
        "ucov((1.024, -0.983, 1.088)e-3, 0.95)",
      ].each do |input|
        it "keeps malformed uncertainty #{input.inspect} on the ordinary fallback" do
          tree = Amath.parse(input, engine: engine)
          expect(uncertainty_nodes(tree)).to be_empty
        end
      end

      ["(3.85 +/- 0.23)e4", "680(41)e-3", "ustd(3.85, 0.23)e4"].each do |input|
        it "keeps #{input.inspect} outside the new shared-exponent call forms" do
          tree = Amath.parse(input, engine: engine)
          expect(texts(tree).inspect).not_to include("shared_exponent")
        end
      end
    end
  end
end
