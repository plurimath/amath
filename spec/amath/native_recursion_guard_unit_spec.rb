# frozen_string_literal: true

RSpec.describe Amath::NativeRecursionGuard do
  it "sets the flag only while the block runs, restoring the outer value" do
    inner = described_class.watch { Thread.current[described_class::KEY] }
    expect(inner).to be(true)
    expect(Thread.current[described_class::KEY]).to be_nil
  end

  it "restores the flag when the block raises" do
    expect { described_class.watch { raise "boom" } }.to raise_error("boom")
    expect(Thread.current[described_class::KEY]).to be_nil
  end

  it "recognises Parsanol's recursion-limit messages" do
    messages = ["Maximum recursion depth (100) exceeded",
                "Recursion limit exceeded at 3", "Expected ')' at 3"]
    expect(messages.map { |m| m.match?(described_class::MESSAGE) })
      .to eq([true, true, false])
  end

  it "keeps NativeRecursionLimit private" do
    expect { Amath::NativeRecursionLimit }.to raise_error(NameError)
  end
end
