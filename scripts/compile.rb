# frozen_string_literal: true

# grammars/<name>.parg -> artifacts/<name>.json (Parsanol PARG artifact)
#                       + artifacts/<name>.bindings.<target>.json
# for both grammars: asciimath (dialect L) and pma (dialect P).
#
# Usage:
#   BUNDLE_GEMFILE=... BUNDLE_PATH=... ruby scripts/compile.rb [--determinism]
#
# The bundle named by BUNDLE_GEMFILE must provide the `parsanol` executable,
# 1.3.131 or later (earlier releases accept --bindings but emit nothing).
# Steps:
#   1. scripts/generate_grammar.rb --check (the .parg matches its inputs)
#   2. bundle exec parsanol parg compile --bindings all
#        -> artifacts/<name>.json and one declared binding artifact per
#           target (parsanol-ruby#432), beside it
#   3. bundle exec parsanol parg check    (artifact matches source + compiler)
#   4. verify every binding artifact: kind, checksum, target, binding
#      version, entries, and pairing with the parse artifact
#   5. --determinism: compile again and require identical bytes for the
#      parse artifact and every binding artifact
#   6. write artifacts/<name>.checksums.txt; the pma one also records the
#      registry edition and the asciiunits artifact the pma grammar was
#      composed with, which must be the installed asciiunits artifact
# Steps 2-6 run for each grammar. Exits nonzero on the first failing step.

require "digest"
require "json"
require "open3"
require "tmpdir"
require_relative "registry"

ROOT = File.expand_path("..", __dir__)
VOCAB = File.join(ROOT, "data/vocabulary.json")
GRAMMARS = %w[asciimath pma].freeze
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

def compile!(grammar, out)
  run!("bundle", "exec", "parsanol", "parg", "compile", grammar, "-o", out, "--bindings", "all")
  missing = BINDING_TARGETS.reject { |target| File.file?(binding_path(out, target)) }
  abort "FAILED: no binding artifact emitted for #{missing.join(', ')}" unless missing.empty?
end

# Every binding artifact loads with Parsanol's own verifier, declares the
# root binding of every entry and pairs with the parse artifact.
def verify_bindings!(artifact)
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
  args = BINDING_TARGETS.flat_map { |target| [target, binding_path(artifact, target)] }
  run!("bundle", "exec", "ruby", "-e", check, artifact, *args)
end

# The checksum of the installed asciiunits artifact, which pma parses
# unit(...) content with.
def asciiunits_checksum
  out = run!("bundle", "exec", "ruby", "-rasciiunits", "-rjson", "-e",
             "puts JSON.parse(File.read(Asciiunits::ARTIFACT_PATH)).fetch('checksum')")
  out.lines.last.strip
end

run!(RbConfig.ruby, "scripts/generate_grammar.rb", "--check")
registry = Registry.load(VOCAB)
relative = ->(path) { path.delete_prefix("#{ROOT}/") }

GRAMMARS.each do |name|
  grammar = File.join(ROOT, "grammars/#{name}.parg")
  artifact = File.join(ROOT, "artifacts/#{name}.json")
  compile!(grammar, artifact)
  run!("bundle", "exec", "parsanol", "parg", "check", "--source", grammar, "--artifact", artifact)
  verify_bindings!(artifact)

  if determinism
    Dir.mktmpdir do |dir|
      again = File.join(dir, "#{name}.json")
      compile!(grammar, again)
      pairs = [[again, artifact]] + BINDING_TARGETS.map { |t| [binding_path(again, t), binding_path(artifact, t)] }
      pairs.each do |fresh, committed|
        next if File.binread(fresh) == File.binread(committed)

        abort "FAILED: recompiled #{File.basename(committed)} is not byte-identical"
      end
      puts "determinism: recompiled #{name} artifact and #{BINDING_TARGETS.size} binding artifacts are byte-identical"
    end
  end

  envelope = JSON.parse(File.binread(artifact))
  lines = [
    "# Written by scripts/compile.rb. Envelope and binding checksums are Parsanol's",
    "# own (PN 2); the sha256 lines are of the files' bytes.",
    "artifact_checksum #{envelope.fetch('checksum')}",
    "compiler_version #{envelope.fetch('compiler_version')}",
    "source_hash sha256:#{envelope.fetch('source_hash')}",
    "#{relative.(artifact)} sha256:#{Digest::SHA256.file(artifact).hexdigest}",
  ]
  BINDING_TARGETS.each do |target|
    path = binding_path(artifact, target)
    payload = JSON.parse(File.binread(path))
    lines << "bindings_#{target}_checksum #{payload.fetch('checksum')} " \
             "binding_version #{payload.fetch('binding_version')}"
    lines << "#{relative.(path)} sha256:#{Digest::SHA256.file(path).hexdigest}"
  end
  lines += [
    "#{relative.(grammar)} sha256:#{Digest::SHA256.file(grammar).hexdigest}",
    "data/vocabulary.json #{Registry::FORMAT} sha256:#{Digest::SHA256.file(VOCAB).hexdigest}",
  ]
  if name == "pma"
    units = registry.fetch("units")
    installed = asciiunits_checksum
    unless installed == units.fetch("checksum")
      abort "FAILED: the installed asciiunits artifact is #{installed}, the registry records #{units['checksum']}"
    end
    lines << "registry_edition #{registry.fetch('edition')}"
    lines << "asciiunits_artifact_checksum #{units['checksum']} #{units['artifact']} #{units['version']}"
  else
    lines << "registry legacy_edition #{registry['legacy_edition'].values_at('edition', 'sha256').join(' ')}"
  end
  lines += [
    "entries #{envelope.fetch('entries').keys.join(' ')}",
    "order_warnings #{envelope.dig('lint', 'order_warnings').size}",
  ]
  checksums = File.join(ROOT, "artifacts/#{name}.checksums.txt")
  File.write(checksums, "#{lines.join("\n")}\n")
  puts File.read(checksums)
end
