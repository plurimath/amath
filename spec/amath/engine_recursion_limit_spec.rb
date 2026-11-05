# frozen_string_literal: true

RSpec.describe Amath::Engine, "native recursion limit" do
  def run(mode, fallback:)
    described_class.run(Amath.artifact, "dot", "x", mode, fallback: fallback)
  end

  before do
    skip "native extension unavailable" unless described_class.native_available?
    allow(Amath.artifact).to receive(:parse).and_call_original
    allow(Amath.artifact).to receive(:parse).with(anything, anything, mode: :native)
      .and_raise(Parsanol::RecursionLimitExceeded,
                 "Recursion limit exceeded: depth 1001 exceeds limit of 1000")
  end

  it "reruns on the Ruby engine under engine: :auto" do
    run(:native, fallback: true)
    expect(described_class.last_engine).to eq(:ruby)
  end

  it "raises NestingTooDeep under engine: :native" do
    expect { run(:native, fallback: false) }
      .to raise_error(Amath::NestingTooDeep, /recursion limit/)
  end

  it "leaves engine: :ruby untouched" do
    run(:ruby, fallback: false)
    expect(described_class.last_engine).to eq(:ruby)
  end
end
