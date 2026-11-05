# frozen_string_literal: true

# Replays the plurimath-testsuite asciimath stage generation pinned in
# spec/fixtures/testsuite-pin.yml through the raw-tree boundary.
#
# Usage:
#   bundle exec ruby scripts/replay_corpus.rb --testsuite PATH [--pin FILE] \
#     [--language asciimath] [--generation N] [--report FILE]
#
# Before any row runs it checks the pin: its schema and fields, that the
# checkout is at the pinned commit with no uncommitted stage files, that the
# ledger has the pinned generation with the pinned snapshot digest, that the
# digest recomputed from the generation's files is the same and that every
# payload has its recorded checksum. --language and --generation, when given,
# must equal the pin's. Then every row of every raw-tree payload is parsed
# with Amath::Parser.raw on the Ruby and the native engine, written as
# scripts/generate_stage_cases.rb writes it, and each outcome must equal the
# row's expected value. Any pin failure, any difference or a generation with
# no raw-tree rows exits 1. The native engine is skipped, and the report says
# so, when the Parsanol extension is missing, unless AMATH_REQUIRE_NATIVE=1.

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "yaml"
require_relative "generate_stage_cases"

module AmathReplayCorpus
  class Error < StandardError; end

  ROOT = File.expand_path("..", __dir__)
  DEFAULT_PIN = File.join(ROOT, "spec", "fixtures", "testsuite-pin.yml")
  PIN_SCHEMA = "plurimath-stage/pin/1"
  PIN_KEYS = %w[schema repository commit language generation snapshot_digest].freeze
  REPOSITORY = "https://github.com/plurimath/plurimath-testsuite"
  LANGUAGE = "asciimath"
  OPTION_KEYS = %w[decimal].freeze

  Pin = Struct.new(:commit, :language, :generation, :digest, keyword_init: true)

  module_function

  # The pin at +path+, its fields checked against plurimath-stage/pin/1.
  def load_pin(path)
    doc = YAML.safe_load_file(path, aliases: false)
    raise Error, "#{path}: not a mapping" unless doc.is_a?(Hash)

    missing = PIN_KEYS - doc.keys
    extra = doc.keys - PIN_KEYS
    raise Error, "#{path}: missing #{missing.join(', ')}" unless missing.empty?
    raise Error, "#{path}: unknown keys #{extra.join(', ')}" unless extra.empty?
    raise Error, "#{path}: schema is not #{PIN_SCHEMA}" unless doc["schema"] == PIN_SCHEMA
    raise Error, "#{path}: repository is not #{REPOSITORY}" unless doc["repository"] == REPOSITORY
    raise Error, "#{path}: commit is not a 40-hex commit" unless doc["commit"].is_a?(String) && doc["commit"].match?(/\A\h{40}\z/)
    raise Error, "#{path}: language #{doc['language'].inspect} is not #{LANGUAGE}" unless doc["language"] == LANGUAGE
    raise Error, "#{path}: generation is not a positive integer" unless doc["generation"].is_a?(Integer) && doc["generation"] >= 1
    unless doc["snapshot_digest"].is_a?(String) && doc["snapshot_digest"].match?(/\Asha256:\h{64}\z/)
      raise Error, "#{path}: snapshot_digest is not sha256:<64 hex>"
    end

    Pin.new(commit: doc["commit"], language: doc["language"], generation: doc["generation"],
            digest: doc["snapshot_digest"])
  rescue Psych::Exception, Errno::ENOENT => e
    raise Error, "#{path}: #{e.message}"
  end

  def git(dir, *args)
    out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise Error, "git #{args.join(' ')} in #{dir}: #{err.strip}" unless status.success?

    out.strip
  end

  # The testsuite's snapshot digest of a generation's { path => bytes }.
  def snapshot_digest(files)
    lines = files.sort_by { |path, _| path.b }.map do |path, bytes|
      "#{Digest::SHA256.hexdigest(bytes)}  #{path}\n"
    end
    "sha256:#{Digest::SHA256.hexdigest(lines.join.encode('UTF-8'))}"
  end

  # [generation dir, { payload path => bytes }] once the checkout matches +pin+.
  def verify(testsuite, pin)
    head = git(testsuite, "rev-parse", "HEAD")
    raise Error, "pin commit #{pin.commit} is not the checkout's HEAD #{head}" unless head == pin.commit

    dirty = git(testsuite, "status", "--porcelain", "--", "stages", "generations")
    raise Error, "testsuite checkout has uncommitted stage files:\n#{dirty}" unless dirty.empty?

    ledger_path = File.join(testsuite, "generations", "#{pin.language}.yaml")
    raise Error, "#{ledger_path} does not exist" unless File.file?(ledger_path)

    entry = YAML.safe_load_file(ledger_path, aliases: false).fetch("entries").find { |e| e["generation"] == pin.generation }
    raise Error, "generations/#{pin.language}.yaml has no generation #{pin.generation}" unless entry
    if entry["snapshot_digest"] != pin.digest
      raise Error, "ledger digest #{entry['snapshot_digest']} of generation #{pin.generation} " \
                   "is not the expected #{pin.digest}"
    end

    dir = File.join(testsuite, entry.fetch("path"))
    paths = Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).reject { |p| File.directory?(File.join(dir, p)) }
    paths.each { |p| raise Error, "#{entry['path']}/#{p} is a symlink" if File.symlink?(File.join(dir, p)) }
    files = paths.to_h { |p| [p, File.binread(File.join(dir, p))] }
    digest = snapshot_digest(files)
    raise Error, "#{entry['path']}: digest #{digest} does not match the ledger's #{pin.digest}" unless digest == pin.digest

    provenance = YAML.safe_load(files.fetch("provenance.yaml") { raise Error, "#{entry['path']} has no provenance.yaml" })
    listed = provenance.fetch("payloads")
    if listed.map { |p| p["path"] }.sort != (files.keys - ["provenance.yaml"]).sort
      raise Error, "#{entry['path']}: provenance does not list exactly the payload files"
    end
    listed.each do |p|
      actual = Digest::SHA256.hexdigest(files.fetch(p["path"]))
      raise Error, "#{entry['path']}/#{p['path']}: sha256 #{actual} is not #{p['sha256']}" unless actual == p["sha256"]
    end
    [entry["path"], listed.to_h { |p| [p["path"], files.fetch(p["path"])] }]
  rescue KeyError, Psych::Exception => e
    raise Error, e.message
  end

  def decode(value, where)
    raise Error, "#{where}: input is not a canonical string" unless value.is_a?(Hash) && value.keys == ["str"] && value["str"].is_a?(String)

    value["str"]
  end

  def decimal(row, where)
    opts = row.fetch("options", {})
    unknown = opts.keys - OPTION_KEYS
    raise Error, "#{where}: unsupported options #{unknown.join(', ')}" unless unknown.empty?

    opts.fetch("decimal", StageCases::DECIMAL)
  end

  # Every raw-tree row of the generation, with its payload path.
  def raw_rows(payloads)
    payloads.flat_map do |rel, bytes|
      doc = YAML.safe_load(bytes, aliases: false)
      next [] unless doc["boundary"] == "raw-tree"

      doc.fetch("cases").map { |row| [rel, row] }
    end
  end

  # The row's outcome on +engine+, in the form the stage payloads record.
  def outcome(input, decimal, engine)
    tree = Amath::Parser.raw(input, decimal: decimal, engine: engine)
    raise Error, "#{input.inspect}: ran on #{Amath.last_engine}, not #{engine}" unless Amath.last_engine == engine

    { "preprocessed" => StageCases.string(input), "tree" => StageCases.tagged(tree, input) }
  rescue Amath::Error => e
    { "error" => e.class.name, "message" => e.message }
  end

  def engines
    return %i[ruby native] if Amath.native_available?
    raise Error, "the native engine is not available" if ENV["AMATH_REQUIRE_NATIVE"] == "1"

    %i[ruby]
  end

  # [failures, { engine => differing row count }]
  def replay(rows, engines)
    counts = engines.to_h { |e| [e.to_s, 0] }
    failures = rows.filter_map do |rel, row|
      where = "#{rel} #{row['id']}"
      input = decode(row.fetch("input"), where)
      dec = decimal(row, where)
      expected = row.fetch("expected")
      wrong = engines.filter_map do |engine|
        actual = outcome(input, dec, engine)
        next if actual == expected

        counts[engine.to_s] += 1
        { "engine" => engine.to_s, "actual" => actual }
      end
      { "id" => row["id"], "payload" => rel, "expected" => expected, "mismatches" => wrong } unless wrong.empty?
    end
    [failures, counts]
  end

  def run(testsuite:, pin: DEFAULT_PIN, language: nil, generation: nil, report: nil, log: $stderr)
    pinned = load_pin(pin)
    raise Error, "--language #{language} is not the pinned #{pinned.language}" if language && language != pinned.language
    if generation && generation != pinned.generation
      raise Error, "--generation #{generation} is not the pinned #{pinned.generation}"
    end

    used = engines
    _dir, payloads = verify(File.expand_path(testsuite), pinned)
    rows = raw_rows(payloads)
    raise Error, "#{pinned.language} generation #{pinned.generation} has no raw-tree rows" if rows.empty?

    log.puts "pin ok: #{pinned.language} generation #{pinned.generation} at #{pinned.commit}, #{pinned.digest}"
    failures, counts = replay(rows, used)
    summary = { "commit" => pinned.commit, "language" => pinned.language, "generation" => pinned.generation,
                "snapshot_digest" => pinned.digest, "engines" => used.map(&:to_s),
                "raw_tree_payloads" => rows.map(&:first).uniq.size, "raw_tree_rows" => rows.size,
                "differing_rows_by_engine" => counts, "mismatched_rows" => failures.size, "failures" => failures }
    if report
      FileUtils.mkdir_p(File.dirname(report))
      File.binwrite(report, "#{JSON.pretty_generate(summary, max_nesting: false)}\n")
    end
    log.puts "#{rows.size} raw-tree rows from #{summary['raw_tree_payloads']} payloads: " \
             "#{counts.map { |e, n| "#{e} #{n} differ" }.join(', ')}"
    log.puts "native engine not available: skipped" unless used.include?(:native)
    raise Error, "#{failures.size} rows differ: #{failures.map { |f| f['id'] }.join(', ')}" unless failures.empty?

    summary
  end

  def main(argv)
    options = {}
    OptionParser.new do |o|
      o.banner = "usage: scripts/replay_corpus.rb --testsuite PATH [--pin FILE] [--language NAME] " \
                 "[--generation N] [--report FILE]"
      o.on("--testsuite PATH") { |v| options[:testsuite] = v }
      o.on("--pin FILE") { |v| options[:pin] = v }
      o.on("--language NAME") { |v| options[:language] = v }
      o.on("--generation N", Integer) { |v| options[:generation] = v }
      o.on("--report FILE") { |v| options[:report] = v }
    end.parse!(argv)
    raise OptionParser::MissingArgument, "--testsuite" unless options[:testsuite]
    raise OptionParser::InvalidOption, argv.join(" ") unless argv.empty?

    run(**options)
    0
  rescue OptionParser::ParseError => e
    warn e.message
    2
  rescue Error => e
    warn "replay_corpus: #{e.message}"
    1
  end
end

exit AmathReplayCorpus.main(ARGV) if $PROGRAM_NAME == __FILE__
