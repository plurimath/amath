# frozen_string_literal: true

# Turns amath's conformance corpora (corpora/*.yml, schema_version 1) into
# raw-tree stage payloads for plurimath-testsuite
# (stages/asciimath/generations/<NNNNNN>/payloads/<group>.yaml, schema
# plurimath-stage/asciimath/cases/1).
#
# Every case is parsed by Amath.parse on each selected engine. The raw tree is
# written in the canonical tagged form of the testsuite's
# docs/tree-parity-contract.adoc. The script stops without writing anything
# when the engines disagree, or when a tree's uncertainty node does not carry
# the source texts the corpus entry records.
#
# Usage:
#
#   bundle exec ruby scripts/generate_stage_cases.rb --out DIR \
#     [--engines native,ruby] [--producer FILE] [CORPUS.yml ...]
#
# With no corpus files it reads every corpora/*.yml. --producer writes the
# producer block for the generation's provenance.yaml (repository, commit,
# generator and input checksums, environment); it needs a clean checkout.
# The output is deterministic: same commit, same bytes.

require "digest"
require "fileutils"
require "open3"
require "yaml"
require_relative "../lib/amath"

# Raw-tree stage payloads from amath's corpora.
module StageCases
  ROOT = File.expand_path("..", __dir__)
  REPOSITORY = "https://github.com/plurimath/amath"
  SCHEMA = "plurimath-stage/asciimath/cases/1"
  DECIMAL = "."
  ENGINES = %i[native ruby].freeze
  HEADER = "# Written by amath scripts/generate_stage_cases.rb. Do not edit.\n"

  module_function

  # Canonical tagged form of one raw-tree value.
  def tagged(value, source)
    case value
    when nil then { "nil" => true }
    when true, false then { "bool" => value }
    when Integer then { "int" => value.to_s }
    when Symbol then { "sym" => value.to_s }
    when String then string(value)
    when Array then { "array" => value.map { |item| tagged(item, source) } }
    when Hash then { "hash" => value.map { |k, v| pair(k, v, source) } }
    when Parsanol::Slice then slice(value, source)
    else raise ArgumentError, "unexpected #{value.class} in the raw tree"
    end
  end

  def pair(key, value, source)
    [tagged(key, source), tagged(value, source)]
  end

  def string(value)
    if value.encoding == Encoding::UTF_8 && value.valid_encoding?
      { "str" => value }
    else
      { "bytes" => value.unpack1("H*"), "encoding" => value.encoding.name }
    end
  end

  def slice(value, source)
    text = value.to_s
    offset = value.offset
    unless source.byteslice(offset, text.bytesize) == text
      raise ArgumentError, "slice #{text.inspect} is not at byte #{offset}"
    end

    { "slice" => text, "byte_offset" => offset,
      "char_offset" => source.byteslice(0, offset).length }
  end

  # The source texts of +value+, as the corpus records them.
  def texts(value)
    case value
    when Hash then value.to_h { |key, child| [key.to_s, texts(child)] }
    when Array then value.map { |child| texts(child) }
    else value.to_s
    end
  end

  def parse(input, engine)
    tree = Amath.parse(input, decimal: DECIMAL, engine: engine)
    return tree if Amath.last_engine == engine

    raise "#{input.inspect}: ran on #{Amath.last_engine}, not #{engine}"
  end

  def expected(entry, engines)
    id = entry.fetch("id")
    input = entry.fetch("input")
    trees = engines.map { |engine| parse(input, engine) }
    dumps = trees.map { |tree| tagged(tree, input) }
    raise "#{id}: the engines return different trees" if dumps.uniq.size > 1

    want = { "expr" => { "sequence" => { "uncertainty" => entry["tree"] } } }
    unless texts(trees.first) == want
      raise "#{id}: tree #{texts(trees.first).inspect} differs from the corpus"
    end

    { "preprocessed" => string(input), "tree" => dumps.first }
  end

  def payload(path, engines)
    corpus = YAML.safe_load_file(path)
    unless corpus["schema_version"] == 1
      raise "#{path}: schema_version is not 1"
    end

    group = File.basename(path, ".yml")
    cases = corpus.fetch("cases").map do |entry|
      { "id" => "#{group}.#{entry.fetch('id')}",
        "input" => string(entry.fetch("input")),
        "options" => { "decimal" => DECIMAL },
        "expected" => expected(entry, engines) }
    end
    { "schema" => SCHEMA, "group" => group,
      "description" => "amath raw trees for corpora/#{group}.yml " \
                       "(#{corpus.fetch('issue')}). Amath.parse has no " \
                       "preprocessing, so preprocessed is the input.",
      "boundary" => "raw-tree", "cases" => cases }
  end

  def git(*command)
    output, status = Open3.capture2("git", "-C", ROOT, *command)
    raise "git #{command.join(' ')} failed" unless status.success?

    output
  end

  def tracked(relative, commit)
    { "repository" => REPOSITORY, "commit" => commit, "path" => relative,
      "sha256" => Digest::SHA256.file(File.join(ROOT, relative)).hexdigest }
  end

  def checksums
    File.readlines(File.join(ROOT, "artifacts/asciimath.checksums.txt"),
                   chomp: true)
      .reject { |line| line.start_with?("#") }
      .to_h { |line| line.split(" ", 2) }
  end

  def lockfile
    specs = Bundler.load.specs.sort_by(&:name)
    { "path" => "Gemfile.lock", "committed" => false,
      "bundler" => Bundler::VERSION,
      "resolved" => specs.to_h { |spec| [spec.name, spec.version.to_s] } }
  end

  def environment(commit)
    sums = checksums
    { "ruby" => { "engine" => RUBY_ENGINE, "version" => RUBY_VERSION },
      "xml_engine" => nil,
      "lockfile" => lockfile,
      "dependencies" => { "parsanol" => Parsanol::VERSION },
      "compiler" => {
        "name" => "parsanol", "version" => sums.fetch("compiler_version"),
        "source_hash" => sums.fetch("source_hash"),
        "artifact_checksum" => sums.fetch("artifact_checksum"),
        "artifact" => tracked("artifacts/asciimath.json", commit)
      },
      "binding" => {
        "ruby_checksum" => sums.fetch("bindings_ruby_checksum").split.first,
        "artifact" => tracked("artifacts/asciimath.bindings.ruby.json", commit),
      },
      "lml" => nil }
  end

  def producer(corpora, engines)
    clean = git("status", "--porcelain").empty?
    raise "--producer needs a clean checkout" unless clean

    commit = git("rev-parse", "HEAD").strip
    inputs = corpora.map { |path| path.delete_prefix("#{ROOT}/") } +
      ["artifacts/asciimath.json"]
    { "kind" => "stage-gem", "repository" => REPOSITORY, "commit" => commit,
      "version" => Amath::VERSION,
      "generator" => tracked("scripts/generate_stage_cases.rb", commit),
      "inputs" => inputs.map { |relative| tracked(relative, commit) },
      "environment" => environment(commit),
      "semantic_boundary" => "raw-tree",
      "configuration" => { "decimal" => DECIMAL,
                           "engines" => engines.map(&:to_s),
                           "entry_point" => "Amath.parse" } }
  end

  def options(argv)
    opts = { engines: ENGINES, corpora: [] }
    args = argv.dup
    until args.empty?
      case (arg = args.shift)
      when "--out" then opts[:out] = File.expand_path(args.shift)
      when "--producer" then opts[:producer] = File.expand_path(args.shift)
      when "--engines" then opts[:engines] = args.shift.split(",").map(&:to_sym)
      when /\A--/ then abort "unknown option #{arg.inspect}"
      else opts[:corpora] << File.expand_path(arg)
      end
    end
    opts
  end

  def check(opts)
    unless opts[:out]
      abort "usage: #{$PROGRAM_NAME} --out DIR [--engines native,ruby] " \
            "[--producer FILE] [CORPUS.yml ...]"
    end
    abort "no corpus files" if opts[:corpora].empty?
    opts[:engines].each do |engine|
      abort "unknown engine #{engine.inspect}" unless ENGINES.include?(engine)
      if engine == :native && !Amath.native_available?
        abort "the native engine is not available"
      end
    end
  end

  def run(argv)
    opts = options(argv)
    glob = File.join(ROOT, "corpora", "*.yml")
    opts[:corpora] = Dir[glob] if opts[:corpora].empty?
    opts[:corpora] = opts[:corpora].sort
    check(opts)
    payloads = opts[:corpora].map { |path| payload(path, opts[:engines]) }
    block = (producer(opts[:corpora], opts[:engines]) if opts[:producer])
    FileUtils.mkdir_p(opts[:out])
    payloads.each do |data|
      File.write(File.join(opts[:out], "#{data['group']}.yaml"),
                 HEADER + YAML.dump(data))
    end
    File.write(opts[:producer], YAML.dump(block)) if block
    rows = payloads.sum { |data| data["cases"].size }
    warn "wrote #{payloads.size} payload(s), #{rows} case(s) to #{opts[:out]}"
  end
end

StageCases.run(ARGV) if $PROGRAM_NAME == __FILE__
