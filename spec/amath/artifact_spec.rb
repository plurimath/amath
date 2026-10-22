# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

RSpec.describe "Amath artifact loading" do
  around do |example|
    Dir.mktmpdir("amath-artifact") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:envelope) { JSON.parse(File.read(SPIKE_ARTIFACT)) }

  def write_artifact(name, body)
    path = File.join(@dir, name)
    File.write(path, body)
    path
  end

  def expect_artifact_error(path, pattern)
    Amath.artifact_path = path
    %i[auto ruby].each do |engine|
      expect { Amath.parse("x", engine: engine) }.to raise_error(Amath::ArtifactError, pattern)
    end
  end

  it "defaults to artifacts/asciimath.json inside the gem" do
    expect(Amath::DEFAULT_ARTIFACT_PATH)
      .to eq(File.expand_path("../../artifacts/asciimath.json", __dir__))
  end

  it "loads the artifact once" do
    expect(Parsanol::PARG::Artifact).to receive(:load).once.and_call_original
    3.times { Amath.parse("x", engine: :ruby) }
  end

  it "reloads after artifact_path= changes" do
    first = Amath.artifact
    Amath.artifact_path = SPIKE_ARTIFACT
    expect(Amath.artifact).not_to equal(first)
  end

  it "raises ArtifactError for a missing file" do
    expect_artifact_error(File.join(@dir, "missing.json"), /artifact not found/)
  end

  it "raises ArtifactError for malformed JSON" do
    expect_artifact_error(write_artifact("malformed.json", "{not json"), /not valid JSON/)
  end

  it "raises ArtifactError for a checksum mismatch" do
    body = JSON.generate(envelope.merge("checksum" => "sha256:#{'0' * 64}"))
    expect_artifact_error(write_artifact("bad-checksum.json", body), /checksum mismatch/)
  end

  it "raises ArtifactError for an unsupported shape even with a valid checksum" do
    changed = envelope.merge("shape" => "parsanol-tree/v999")
    changed["checksum"] = Parsanol::PARG::Compiler.checksum(changed)
    expect(changed["checksum"]).not_to eq(envelope["checksum"])
    expect_artifact_error(write_artifact("unsupported-shape.json", JSON.generate(changed)),
                          /unsupported artifact shape/)
  end

  it "raises ArtifactError when a decimal entry is missing" do
    changed = envelope.merge("entries" => envelope["entries"].except("arabic"))
    changed["checksum"] = Parsanol::PARG::Compiler.checksum(changed)
    expect_artifact_error(write_artifact("no-arabic.json", JSON.generate(changed)),
                          /lacks required entries: arabic/)
  end

  it "raises ArtifactError for a non-object envelope" do
    expect_artifact_error(write_artifact("array.json", "[]"), /invalid/)
  end
end
