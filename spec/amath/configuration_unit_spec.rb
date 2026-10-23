# frozen_string_literal: true

RSpec.describe Amath::Configuration do
  it "maps every decimal marker to an artifact entry" do
    expect(described_class::DECIMAL_ENTRIES)
      .to eq("." => "dot", "," => "comma", "٫" => "arabic")
  end

  it "lists the engines" do
    expect(described_class::ENGINES).to eq(%i[auto native ruby])
  end

  it "is re-exported by Amath" do
    expect(Amath::DECIMAL_ENTRIES).to equal(described_class::DECIMAL_ENTRIES)
    expect(Amath::ENGINES).to equal(described_class::ENGINES)
    expect(Amath::DEFAULT_ARTIFACT_PATH)
      .to equal(described_class::DEFAULT_ARTIFACT_PATH)
  end
end
