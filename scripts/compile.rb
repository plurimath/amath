# frozen_string_literal: true

# grammars/asciimath.parg -> artifacts/asciimath.json (Parsanol PARG artifact)
#
# Usage:
#   BUNDLE_GEMFILE=... BUNDLE_PATH=... ruby scripts/compile.rb [--determinism]
#
# The bundle named by BUNDLE_GEMFILE must provide the `parsanol` executable
# (1.3.109 was used for the committed artifact). Steps:
#   1. scripts/generate_grammar.rb --check (the .parg matches its inputs)
#   2. bundle exec parsanol parg compile  -> artifacts/asciimath.json
#   3. bundle exec parsanol parg check    (artifact matches source + compiler)
#   4. --determinism: compile again and require identical bytes
#   5. write artifacts/asciimath.checksums.txt
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

determinism = ARGV.delete("--determinism")
abort "usage: ruby scripts/compile.rb [--determinism]" unless ARGV.empty?

def run!(*cmd)
  out, status = Open3.capture2e(*cmd, chdir: ROOT)
  puts out
  abort "FAILED (exit #{status.exitstatus}): #{cmd.join(' ')}" unless status.success?
  out
end

run!(RbConfig.ruby, "scripts/generate_grammar.rb", "--check")
run!("bundle", "exec", "parsanol", "parg", "compile", GRAMMAR, "-o", ARTIFACT)
run!("bundle", "exec", "parsanol", "parg", "check", "--source", GRAMMAR, "--artifact", ARTIFACT)

if determinism
  Dir.mktmpdir do |dir|
    again = File.join(dir, "asciimath.json")
    run!("bundle", "exec", "parsanol", "parg", "compile", GRAMMAR, "-o", again)
    abort "FAILED: recompilation is not byte-identical" unless File.binread(again) == File.binread(ARTIFACT)
    puts "determinism: recompiled artifact is byte-identical"
  end
end

envelope = JSON.parse(File.binread(ARTIFACT))
lines = [
  "# Written by scripts/compile.rb. Envelope checksum is Parsanol's own (PN 2);",
  "# the sha256 lines are of the files' bytes.",
  "artifact_checksum #{envelope.fetch('checksum')}",
  "compiler_version #{envelope.fetch('compiler_version')}",
  "source_hash sha256:#{envelope.fetch('source_hash')}",
  "artifacts/asciimath.json sha256:#{Digest::SHA256.file(ARTIFACT).hexdigest}",
  "grammars/asciimath.parg sha256:#{Digest::SHA256.file(GRAMMAR).hexdigest}",
  "data/vocabulary.json sha256:#{Digest::SHA256.file(VOCAB).hexdigest}",
  "entries #{envelope.fetch('entries').keys.join(' ')}",
  "order_warnings #{envelope.dig('lint', 'order_warnings').size}",
]
File.write(CHECKSUMS, "#{lines.join("\n")}\n")
puts File.read(CHECKSUMS)
