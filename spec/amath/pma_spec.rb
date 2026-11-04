# frozen_string_literal: true

require "tmpdir"
require "yaml"

# pma (dialect P): every accepted and refused example of plurimath
# docs/pma.adoc, kept as the staging corpus corpora/pma/*.yml, on both
# engines.
RSpec.describe "Amath.parse(input, dialect: :pma)" do
  corpus = File.expand_path("../../corpora/pma", __dir__)
  accepted = YAML.safe_load_file(File.join(corpus, "accepted.yml")).fetch("cases")
  refused = YAML.safe_load_file(File.join(corpus, "refused.yml")).fetch("cases")
  engines = %i[ruby native]

  def texts(value)
    case value
    when Hash then value.to_h { |k, v| [k.to_s, texts(v)] }
    else value.to_s
    end
  end

  # The set fields of a model object, as source texts.
  def fields(model)
    model.class.attributes.keys.each_with_object({}) do |name, out|
      next if %i[value kind].include?(name) && model.respond_to?(:spelling)

      value = model.public_send(name)
      next if value.nil?

      out[name.to_s] = value.is_a?(Lutaml::Model::Serializable) ? fields(value) : value
    end
  end

  before { Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH }

  it "has a corpus row for every refusal category" do
    expect(refused.map { |c| c["category"] }.uniq).to match_array(Amath::Pma::Refusal::CATEGORIES)
  end

  engines.each do |engine|
    context "with engine: #{engine.inspect}" do
      before { require_native! if engine == :native }

      accepted.each do |c|
        it "accepts #{c['id']}: #{c['input']}" do
          document = Amath.parse(c["input"], dialect: :pma, engine: engine)
          expect(document).to be_a(Amath::Model::PmaDocument)
          expect(fields(document.term)).to eq(c["term"])
          expect(Amath.last_engine).to eq(engine)
        end
      end

      refused.each do |c|
        it "refuses #{c['id']}: #{c['input']} (#{c['category']})" do
          expect { Amath.parse(c["input"], dialect: :pma, engine: engine) }
            .to raise_error(Amath::ParseError) { |e|
              expect([e.category, e.byte_offset, e.char_offset, e.input])
                .to eq([c["category"], c["byte_offset"], c["char_offset"], c["input"]])
            }
        end
      end

      it "builds the dialect L Uncertainty and Unit classes" do
        term = Amath.parse("(10.3 +/- 0.2 ~rect) unit(cm)", dialect: :pma, engine: engine).term
        expect(term.uncertainty).to be_a(Amath::Model::Uncertainty)
        expect(term.uncertainty.unit).to be_a(Amath::Model::Unit)
        expect(term.uncertainty.distribution).to eq("rect")
      end

      it "refuses deep brackets without a stack error" do
        ["(" * 5000, "unit(#{'(' * 5000}m#{')' * 5000})", "diff(#{'(' * 5000}"].each do |input|
          expect { Amath.parse(input, dialect: :pma, engine: engine) }
            .to raise_error(Amath::ParseError) { |e| expect(e).not_to be_a(Amath::NestingTooDeep) }
        end
      end
    end
  end

  describe "selection" do
    it "defaults to dialect L" do
      expect(Amath.parse("ustd(1.2, 0.1)")).to be_a(Amath::Model::Document)
      expect(Amath.parse("ustd(1.2, 0.1)", dialect: :legacy)).to be_a(Amath::Model::Document)
    end

    it "raises ArgumentError for an unknown dialect before loading an artifact" do
      expect { Amath.parse("x", dialect: :pmb) }.to raise_error(ArgumentError, /unknown dialect :pmb/)
      expect { Amath.parse("x", dialect: "pma") }.to raise_error(ArgumentError, /unknown dialect/)
    end

    it "has no decimal: option for pma" do
      expect { Amath.parse("(1,2 +/- 0,1)", dialect: :pma, decimal: ",") }
        .to raise_error(ArgumentError, /no decimal: option/)
      expect(Amath.parse("(1.2 +/- 0.1)", dialect: :pma, decimal: ".")).to be_a(Amath::Model::PmaDocument)
    end

    it "never falls back to the other dialect" do
      expect { Amath.parse("x + y", dialect: :pma) }.to raise_error(Amath::ParseError) { |e|
        expect(e.category).to eq("no-production")
      }
      legacy = Amath.parse("(10.3 +/- 0.2 ~rect)")
      expect(legacy).to be_a(Amath::Model::Document)
    end

    it "leaves the category of a dialect L ParseError nil" do
      error = Amath::ParseError.new("x", input: "x", byte_offset: 0, char_offset: 0)
      expect(error.category).to be_nil
    end

    it "loads only the pma artifact, and fails without it" do
      original = Amath::Pma.artifact.path
      Amath::Pma.artifact.path = File.join(Dir.tmpdir, "no-such-pma.json")
      expect { Amath.parse("(1.0 +/- 0.1)", dialect: :pma) }.to raise_error(Amath::ArtifactError)
      expect(Amath.parse("x")).to be_a(Amath::Model::Document)
    ensure
      Amath::Pma.artifact.path = original
    end
  end
end
