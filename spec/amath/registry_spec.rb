# frozen_string_literal: true

require "digest"
require_relative "../../scripts/registry"
require_relative "../../scripts/check_reserved_words"

RSpec.describe "registry v2 (data/vocabulary.json)" do
  let(:data) { Registry.load }
  let(:root) { File.expand_path("../..", __dir__) }

  it "is in the v2 format with a dialect and a declared binding on every entry" do
    expect(data["format"]).to eq("amath-vocabulary/v2")
    expect(data["entries"].map { |e| e["dialect"] }.uniq - Registry::DIALECTS).to be_empty
    expect(data["entries"].map { |e| e["binding"] }.uniq - data["bindings"].keys).to be_empty
  end

  it "serializes back to its own bytes" do
    expect(Registry.dump(data)).to eq(File.read(Registry::PATH, encoding: "UTF-8"))
  end

  it "projects its dialect L entries onto the pinned legacy edition" do
    bytes = Registry.legacy_bytes(data)
    expect("sha256:#{Digest::SHA256.hexdigest(bytes)}").to eq(data["legacy_edition"]["sha256"])
  end

  it "keeps the pinned edition hash in the generated dialect L grammar header" do
    header = File.foreach(File.join(root, "grammars/asciimath.parg")).grep(/data\/vocabulary\.json sha256:/).first
    expect(header).to include(data["legacy_edition"]["sha256"].delete_prefix("sha256:"))
  end

  it "keeps pma-only entries out of the dialect L projection" do
    pma = data["entries"].select { |e| e["dialect"] == "pma" }
    expect(pma.map { |e| e["value"] }).to eq(%w[rect triang arcsine])
    expect(Registry.entries(data, "legacy")).not_to include(*pma)
    projected = Registry.legacy_v1(data).to_json
    expect(projected).not_to include("distribution_names")
  end

  it "refuses a dialect L change that is not a new edition" do
    changed = Marshal.load(Marshal.dump(data))
    changed["entries"].first["dialect"] = "pma"
    expect { Registry.check!(changed) }.to raise_error(SystemExit)
  end

  describe "reserved-word collision check" do
    let(:reserved) { data["reserved_words"] }

    it "reserves the six pma words" do
      expect(reserved).to eq(%w[unit ustd uexp ucov diff quantity])
    end

    it "finds no collision with the registry spellings" do
      expect(ReservedWords.collisions(reserved, "registry" => Registry.spellings(data))).to be_empty
    end

    it "reports a collision, case-insensitively, with its source" do
      sources = { "registry" => %w[x Diff], "unitsdb" => %w[m unit] }
      expect(ReservedWords.collisions(reserved, sources))
        .to contain_exactly(%w[unit unitsdb unit], %w[diff registry Diff])
    end

    it "reads unitsdb unit symbols and names" do
      units = { "units" => [{ "names" => [{ "value" => "metre" }], "short" => "meter",
                              "symbols" => [{ "ascii" => "m", "unicode" => "m", "id" => "m" }] }] }
      expect(ReservedWords.unitsdb_texts(units)).to contain_exactly("metre", "meter", "m")
    end
  end
end
