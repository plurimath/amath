# frozen_string_literal: true

require "digest"
require "tmpdir"
require "yaml"
require_relative "../../scripts/generate_stage_cases"

# scripts/generate_stage_cases.rb --boundary typed-model: typed-model rows
# written from the bound data, checked against the built model.
RSpec.describe "StageCases typed-model rows" do
  root = File.expand_path("../..", __dir__)

  before(:all) do
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
    @artifact = Amath.artifact
    @bindings = Amath.bindings
  end

  before do
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
    allow(Amath).to receive_messages(artifact: @artifact, bindings: @bindings)
  end

  def fields(node)
    node.fetch("fields").to_h
  end

  %i[native ruby].each do |engine|
    context "with engine: #{engine.inspect}" do
      before { require_native! if engine == :native }

      it "writes the Document from the bound data, equal to a walk of the built model" do
        dump, document = StageCases.model("alpha + 1", engine)
        expect(dump).to eq(StageCases.model_walk(document))
        expect(dump["node"]).to eq("Amath::Model::Document")
        expect(dump["fields"].map(&:first)).to eq(%w[expression decimal])
        expect(fields(dump)["decimal"]).to eq("str" => ".")
      end

      it "keeps collections as arrays and writes MathSymbol's derived value and kind" do
        dump, = StageCases.model("alpha + 1", engine)
        chain = fields(fields(fields(dump)["expression"])["expr"])["amath_chain"]
        items = chain.fetch("array")
        expect(items.map { |item| item["node"] }.uniq).to eq(["Amath::Model::AmathChainItem"])
        step = fields(fields(items.first)["amath_step"])
        symbol = fields(step["sequence"])["symbol"]
        expect(symbol).to eq(
          "node" => "Amath::Model::MathSymbol",
          "fields" => [["spelling", { "str" => "alpha" }], ["value", { "str" => "α" }],
                       ["kind", { "str" => "symbol" }]],
        )
      end
    end
  end

  it "writes fields in declaration order and leaves nil fields out" do
    data = { "kind" => nil, "spelling" => "x" }
    expect(StageCases.model_node(Amath::Model::Document, { "decimal" => "," }, "/"))
      .to eq("node" => "Amath::Model::Document", "fields" => [["decimal", { "str" => "," }]])
    expect(StageCases.model_node(Amath::Model::MathSymbol, data, "/")["fields"].map(&:first))
      .to eq(%w[spelling value kind])
  end

  it "stops on data the model does not declare" do
    expect { StageCases.model_node(Amath::Model::Document, { "nope" => "1" }, "/") }
      .to raise_error(/Amath::Model::Document has no attribute nope/)
    expect { StageCases.model_node(Amath::Model::Document, { "decimal" => ["."] }, "/") }
      .to raise_error(%r{/decimal: Array for a})
  end

  it "writes model-<group> payloads with <id>.model rows from both engines" do
    require_native!
    corpus = File.join(root, "corpora/uncertainty-shared-exponent.yml")
    data = StageCases.payload(corpus, StageCases::ENGINES, "typed-model")
    expect(data["group"]).to eq("model-uncertainty-shared-exponent")
    expect(data["boundary"]).to eq("typed-model")
    ids = YAML.safe_load_file(corpus).fetch("cases").map { |c| "uncertainty-shared-exponent.#{c['id']}.model" }
    expect(data["cases"].map { |c| c["id"] }).to eq(ids)
    expect(data["cases"].map { |c| c.dig("expected", "tree", "node") }.uniq).to eq(["Amath::Model::Document"])
  end

  it "names the committed LML export and its checksum" do
    lml = StageCases.lml("0" * 40)
    sha = Digest::SHA256.file(File.join(root, StageCases::LML)).hexdigest
    expect(lml).to include("format" => "amath-lml/1", "checksum" => "sha256:#{sha}")
    expect(lml["models"]).to eq(Amath::Model.classes.size)
    expect(lml["export"]).to include("path" => "model/asciimath.lml.json", "sha256" => sha)
  end

  it "refuses an unknown boundary" do
    Dir.mktmpdir do |dir|
      out, status = Open3.capture2e(RbConfig.ruby, File.join(root, "scripts/generate_stage_cases.rb"),
                                    "--out", dir, "--boundary", "model")
      expect(status).not_to be_success
      expect(out).to include("unknown boundary")
    end
  end
end
