# frozen_string_literal: true

require "digest"
require "json"

# The declared per-target binding artifacts written by scripts/compile.rb
# beside artifacts/asciimath.json (parsanol-ruby#432).
RSpec.describe "declared binding artifacts" do
  targets = %w[ruby rs ts python]
  artifacts_dir = File.expand_path("../../artifacts", __dir__)
  binding_path = ->(target) { File.join(artifacts_dir, "asciimath.bindings.#{target}.json") }
  load_binding = lambda do |json, target|
    Parsanol::PARG::Bindings::Artifact.from_json(json, target: target)
  end

  let(:parse_artifact) { Parsanol::PARG::Artifact.load(Amath::DEFAULT_ARTIFACT_PATH) }

  it "covers every binding target Parsanol knows" do
    expect(targets).to eq(Parsanol::PARG::Bindings::Artifact::TARGETS)
  end

  targets.each do |target|
    context "with target #{target}" do
      let(:json) { File.read(binding_path.call(target)) }

      it "loads, verifies and pairs with the bundled parse artifact" do
        art = load_binding.call(json, target)
        expect(art.pair_with!(parse_artifact)).to equal(art)
        expect(art.target).to eq(target)
        expect(art.binding_version).to eq(1)
      end

      it "declares one whole-tree root binding per decimal entry" do
        art = load_binding.call(json, target)
        expect(art.entry_names).to eq(Amath::DECIMAL_ENTRIES.values)
        art.entry_names.each do |name|
          expect(art.bindings(name).map(&:compact)).to eq(
            [{ "capture" => "root", "path" => "root", "type" => "any" }],
          )
        end
      end

      it "carries the same records as the parse artifact" do
        art = load_binding.call(json, target)
        art.entry_names.each do |name|
          expect(art.bindings(name)).to eq(parse_artifact.entry(name)["bindings"])
        end
      end

      it "rejects a tampered payload" do
        payload = JSON.parse(json)
        payload["entries"]["dot"]["bindings"][0]["path"] = "other"
        expect { load_binding.call(JSON.generate(payload), target) }
          .to raise_error(Parsanol::PARG::ArtifactError, /checksum mismatch/)
      end

      it "rejects being loaded as another target" do
        other = (targets - [target]).first
        expect { load_binding.call(json, other) }
          .to raise_error(Parsanol::PARG::ArtifactError, /targets "#{target}"/)
      end

      it "does not pair with another grammar's parse artifact" do
        art = load_binding.call(json, target)
        spike = Parsanol::PARG::Artifact.load(SPIKE_ARTIFACT)
        expect { art.pair_with!(spike) }
          .to raise_error(Parsanol::PARG::ArtifactError, /does not pair/)
      end

      it "is recorded with its bytes and checksum in the checksum manifest" do
        manifest = File.read(File.join(artifacts_dir, "asciimath.checksums.txt"))
        name = "artifacts/asciimath.bindings.#{target}.json"
        expect(manifest).to include("#{name} sha256:#{Digest::SHA256.hexdigest(json)}")
        expect(manifest).to include(
          "bindings_#{target}_checksum #{JSON.parse(json).fetch('checksum')} binding_version 1",
        )
      end
    end
  end

  it "binds the whole parse tree, as plain data, under root" do
    art = load_binding.call(File.read(binding_path.call("ruby")), "ruby")
    art.pair_with!(parse_artifact)
    tree = parse_artifact.parse("dot", "x/y", mode: :ruby)
    bound = art.apply("dot", tree)
    expect(bound.keys).to eq([:root])
    expect(bound[:root]).to eq(Parsanol::PARG::Bindings.plain(tree[:root]))
  end
end
