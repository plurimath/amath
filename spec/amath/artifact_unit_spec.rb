# frozen_string_literal: true

RSpec.describe Amath::Artifact do
  subject(:artifact) { described_class.new(SPIKE_ARTIFACT) }

  it "loads the artifact once" do
    expect(Parsanol::PARG::Artifact).to receive(:load).once.and_call_original
    first = artifact.fetch
    expect(artifact.fetch).to equal(first)
  end

  it "reloads after the path changes" do
    first = artifact.fetch
    artifact.path = Pathname(SPIKE_ARTIFACT)
    expect(artifact.path).to eq(SPIKE_ARTIFACT)
    expect(artifact.fetch).not_to equal(first)
  end

  it "maps a missing file to ArtifactError" do
    expect { described_class.load("/nonexistent/amath.json") }
      .to raise_error(Amath::ArtifactError, /artifact not found/)
  end
end
