# frozen_string_literal: true

# grammars/asciimath.parg -> artifacts/asciimath.json (Parsanol PARG artifact)
#                         + artifacts/asciimath.bindings.<target>.json
#
# Usage:
#   BUNDLE_GEMFILE=... BUNDLE_PATH=... ruby scripts/compile.rb [--determinism]
#
# The bundle named by BUNDLE_GEMFILE must provide the `parsanol` executable,
# 1.3.131 or later (earlier releases accept --bindings but emit nothing).
# Steps:
#   1. scripts/generate_grammar.rb --check (the .parg matches its inputs)
#   2. bundle exec parsanol parg compile --bindings all
#        -> artifacts/asciimath.json and one declared binding artifact per
#           target (parsanol-ruby#432), beside it
#   3. bundle exec parsanol parg check    (artifact matches source + compiler)
#   4. verify every binding artifact: kind, checksum, target, binding
#      version, entries, and pairing with the parse artifact
#   5. --determinism: compile again and require identical bytes for the
#      parse artifact and every binding artifact
#   6. write artifacts/asciimath.checksums.txt
# Exits nonzero on the first failing step.

require "digest"
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
GRAMMAR = File.join(ROOT, "grammars/asciimath.parg")
VOCAB = File.join(ROOT, "data/vocabulary.json")
ARTIFACT = File.join(ROOT, "artifacts/asciimath.json")
CHECKSUMS = File.join(ROOT, "artifacts/asciimath.checksums.txt")
# Parsanol::PARG::Bindings::Artifact::TARGETS, in its order.
BINDING_TARGETS = %w[ruby rs ts python].freeze

determinism = ARGV.delete("--determinism")
abort "usage: ruby scripts/compile.rb [--determinism]" unless ARGV.empty?

def run!(*cmd)
  out, status = Open3.capture2e(*cmd, chdir: ROOT)
  puts out
  abort "FAILED (exit #{status.exitstatus}): #{cmd.join(' ')}" unless status.success?
  out
end

# The binding artifact the compiler writes beside +artifact+ for +target+.
def binding_path(artifact, target)
  artifact.sub(/\.json\z/, ".bindings.#{target}.json")
end

def compile!(out)
  run!("bundle", "exec", "parsanol", "parg", "compile", GRAMMAR, "-o", out, "--bindings", "all")
  missing = BINDING_TARGETS.reject { |target| File.file?(binding_path(out, target)) }
  abort "FAILED: no binding artifact emitted for #{missing.join(', ')}" unless missing.empty?
end

# Every binding artifact loads with Parsanol's own verifier, declares the
# root binding of every entry and pairs with the parse artifact.
def verify_bindings!
  check = <<~RUBY
    require "parsanol"
    require "parsanol/parg"
    parse = Parsanol::PARG::Artifact.load(ARGV.shift)
    expected = parse.entries.to_h { |name| [name, parse.entry(name)["bindings"]] }
    ARGV.each_slice(2) do |target, path|
      art = Parsanol::PARG::Bindings::Artifact.from_json(File.read(path), target: target)
      art.pair_with!(parse)
      abort "\#{path}: entries \#{art.entry_names.inspect} != \#{expected.keys.inspect}" unless art.entry_names == expected.keys
      expected.each do |name, records|
        abort "\#{path}: entry \#{name} has no bindings" if records.to_a.empty?
        abort "\#{path}: entry \#{name} bindings differ from the parse artifact" unless art.bindings(name) == records
      end
      puts "bindings: \#{File.basename(path)} target=\#{art.target} version=\#{art.binding_version} paired"
    end
  RUBY
  args = BINDING_TARGETS.flat_map { |target| [target, binding_path(ARTIFACT, target)] }
  run!("bundle", "exec", "ruby", "-e", check, ARTIFACT, *args)
end

run!(RbConfig.ruby, "scripts/generate_grammar.rb", "--check")
compile!(ARTIFACT)
run!("bundle", "exec", "parsanol", "parg", "check", "--source", GRAMMAR, "--artifact", ARTIFACT)
verify_bindings!

if determinism
  Dir.mktmpdir do |dir|
    again = File.join(dir, "asciimath.json")
    compile!(again)
    pairs = [[again, ARTIFACT]] + BINDING_TARGETS.map { |t| [binding_path(again, t), binding_path(ARTIFACT, t)] }
    pairs.each do |fresh, committed|
      next if File.binread(fresh) == File.binread(committed)

      abort "FAILED: recompiled #{File.basename(committed)} is not byte-identical"
    end
    puts "determinism: recompiled artifact and #{BINDING_TARGETS.size} binding artifacts are byte-identical"
  end
end

envelope = JSON.parse(File.binread(ARTIFACT))
relative = ->(path) { path.delete_prefix("#{ROOT}/") }
lines = [
  "# Written by scripts/compile.rb. Envelope and binding checksums are Parsanol's",
  "# own (PN 2); the sha256 lines are of the files' bytes.",
  "artifact_checksum #{envelope.fetch('checksum')}",
  "compiler_version #{envelope.fetch('compiler_version')}",
  "source_hash sha256:#{envelope.fetch('source_hash')}",
  "#{relative.(ARTIFACT)} sha256:#{Digest::SHA256.file(ARTIFACT).hexdigest}",
]
BINDING_TARGETS.each do |target|
  path = binding_path(ARTIFACT, target)
  payload = JSON.parse(File.binread(path))
  lines << "bindings_#{target}_checksum #{payload.fetch('checksum')} " \
           "binding_version #{payload.fetch('binding_version')}"
  lines << "#{relative.(path)} sha256:#{Digest::SHA256.file(path).hexdigest}"
end
lines += [
  "grammars/asciimath.parg sha256:#{Digest::SHA256.file(GRAMMAR).hexdigest}",
  "data/vocabulary.json sha256:#{Digest::SHA256.file(VOCAB).hexdigest}",
  "entries #{envelope.fetch('entries').keys.join(' ')}",
  "order_warnings #{envelope.dig('lint', 'order_warnings').size}",
]
File.write(CHECKSUMS, "#{lines.join("\n")}\n")
puts File.read(CHECKSUMS)
