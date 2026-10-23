# frozen_string_literal: true

RSpec.describe Amath::ErrorPosition do
  let(:cause_class) { Struct.new(:position, :children) }

  def cause(position, *children)
    cause_class.new(position, children)
  end

  # An artifact whose Tree-reporter reparse raises +failure+ (or accepts).
  def artifact_rejecting(failure)
    atom = Object.new
    atom.define_singleton_method(:parse) do |*|
      failure ? raise(failure) : "accepted"
    end
    instance_double(Parsanol::PARG::Artifact, root_atom: atom)
  end

  it "reports the deepest leaf of the Tree reporter's causes" do
    tree = cause(9, cause(4), cause(nil, cause(6), cause(2)))
    failure = Parsanol::ParseFailed.new("rejected", tree)
    artifact = artifact_rejecting(failure)
    expect(described_class.byte_offset(failure, artifact, "dot", "x")).to eq(6)
  end

  it "falls back to the deepest cause when the reparse accepts" do
    failure = Parsanol::ParseFailed.new("rejected", cause(3, cause(7)))
    artifact = artifact_rejecting(nil)
    expect(described_class.byte_offset(failure, artifact, "dot", "x")).to eq(7)
  end

  it "converts a byte offset into a character offset" do
    expect(described_class.char_offset("éé x", 4)).to eq(2)
  end
end
