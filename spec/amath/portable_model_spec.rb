# frozen_string_literal: true

require "json"

RSpec.describe "portable symbol declarations" do
  it "keeps direct construction and live spelling reads" do
    symbol = Amath::Model::MathSymbol.new(spelling: "alpha")
    defaults = [symbol.using_default?(:value), symbol.using_default?(:kind)]
    expect([symbol.value, symbol.kind]).to eq(["α", "symbol"])
    expect([symbol.using_default?(:value), symbol.using_default?(:kind)]).to eq(defaults)
    expect(JSON.parse(symbol.to_json)).to eq("spelling" => "alpha", "value" => "α", "kind" => "symbol")
    symbol.spelling = "->"
    expect([symbol.value, symbol.kind]).to eq(["→", "symbol"])
    symbol.spelling.replace("unlisted")
    expect([symbol.value, symbol.kind]).to eq(["unlisted", "unlisted"])
    symbol.spelling = nil
    expect([symbol.value, symbol.kind]).to eq([nil, nil])
  end

  it "retains the derived getter when a caller assigns a resolved slot" do
    symbol = Amath::Model::MathSymbol.new(spelling: "alpha", value: "wrong", kind: "wrong")
    expect([symbol.value, symbol.kind]).to eq(["α", "symbol"])
    expect(JSON.parse(symbol.to_json)).to eq("spelling" => "alpha", "value" => "α", "kind" => "symbol")
  end

  it "exports value and kind as typed data" do
    klass = Amath::Model::MathSymbol
    expect(klass.attributes[:value].options).not_to have_key(:method_name)
    expect(klass.attributes[:kind].options).not_to have_key(:method_name)
    expect(Lutaml::Model::Lml.export(klass).to_h.fetch("attributes").map { |a| a.fetch("name") })
      .to include("spelling", "value", "kind")
  end
end
