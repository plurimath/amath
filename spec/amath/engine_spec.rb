# frozen_string_literal: true

RSpec.describe "Amath engine policy" do
  context "when the native extension is available" do
    before { require_native! }

    it "engine: :auto runs the native engine" do
      expect(Parsanol::Native).to receive(:parse).and_call_original
      Amath.parse("sinh x")
      expect(Amath.last_engine).to eq(:native)
    end

    it "engine: :native runs the native engine" do
      expect(Parsanol::Native).to receive(:parse).and_call_original
      Amath.parse("sinh x", engine: :native)
      expect(Amath.last_engine).to eq(:native)
    end

    it "engine: :ruby never calls the native engine" do
      expect(Parsanol::Native).not_to receive(:parse)
      Amath.parse("sinh x", engine: :ruby)
      expect(Amath.last_engine).to eq(:ruby)
    end

    it "both engines return the same tree" do
      input = "text(a b) sin x_1.5"
      expect(Amath.parse(input, engine: :native)).to eq(Amath.parse(input, engine: :ruby))
    end
  end

  context "when the native extension is unavailable" do
    before { allow(Parsanol::Native).to receive(:available?).and_return(false) }

    it "engine: :native raises EngineUnavailable instead of running Ruby" do
      expect(Parsanol::Native).not_to receive(:parse)
      expect { Amath.parse("sinh x", engine: :native) }
        .to raise_error(Amath::EngineUnavailable, /native extension is not available/)
    end

    it "engine: :auto runs the Ruby engine" do
      expect(Parsanol::Native).not_to receive(:parse)
      tree = Amath.parse("sinh x")
      expect(tree[:expr][:sequence][:unary][:unary_class].to_s).to eq("sinh")
      expect(Amath.last_engine).to eq(:ruby)
    end
  end

  it "keeps last_engine per thread" do
    Amath.parse("x", engine: :ruby)
    other = Thread.new { Amath.last_engine }.value
    expect(other).to be_nil
    expect(Amath.last_engine).to eq(:ruby)
  end
end
