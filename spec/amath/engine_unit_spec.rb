# frozen_string_literal: true

RSpec.describe Amath::Engine do
  describe ".resolve" do
    it "runs Ruby for engine: :ruby" do
      expect(described_class.resolve(:ruby)).to eq(:ruby)
    end

    it "picks Ruby under :auto without the native extension" do
      allow(Parsanol::Native).to receive(:available?).and_return(false)
      expect(described_class.resolve(:auto)).to eq(:ruby)
    end

    it "rejects an unknown engine" do
      expect { described_class.resolve(:jit) }
        .to raise_error(ArgumentError, /unknown engine :jit/)
    end
  end

  it "reports the native extension as unavailable when probing fails" do
    allow(Parsanol::Native).to receive(:available?).and_raise(LoadError)
    expect(described_class.native_available?).to be(false)
  end

  it "records the engine that ran per thread" do
    described_class.run(Amath.artifact, "dot", "x", :ruby, fallback: false)
    expect(described_class.last_engine).to eq(:ruby)
  end

  it "keeps deep input off native on other threads without fallback" do
    input = "#{'(' * 30}x#{')' * 30}"
    error = Thread.new do
      described_class.run(Amath.artifact, "dot", input, :native,
                          fallback: false)
    rescue Amath::NestingTooDeep => e
      e
    end.value
    expect(error.message).to include("nesting depth over 25 off the main")
  end
end
