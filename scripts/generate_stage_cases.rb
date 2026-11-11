# frozen_string_literal: true

# Turns amath's conformance corpora (corpora/*.yml, schema_version 1) into
# stage payloads for plurimath-testsuite
# (stages/asciimath/generations/<NNNNNN>/payloads/<group>.yaml, schema
# plurimath-stage/asciimath/cases/1), at one of two boundaries:
#
# raw-tree (the default): every case is parsed by Amath::Parser.raw (the
# internal raw-tree boundary) on each selected engine, and the raw tree is
# written to <group>.yaml.
#
# typed-model: every case is parsed by Amath.parse_model on each selected engine,
# and the typed model (Amath::Model::Document) is written to
# model-<group>.yaml with row ids "<id>.model". The rows are written from
# the bound data the model is built from (the artifact's `(any)` binding
# output), typed by the declared model attributes: each object is
# {node: <model class>, fields: [...]} with its set fields in declaration
# order (nil fields are left out) and derived fields (MathSymbol value and
# kind) as the model computes them. The same walk over the built model must
# give the same rows, so the rows are the model.
#
# Values are written in the canonical tagged form of the testsuite's
# docs/tree-parity-contract.adoc. The script stops without writing anything
# when the engines disagree, when a tree's uncertainty node does not carry
# the source texts the corpus entry records, or (typed-model) when the
# bound data and the built model differ.
#
# Usage:
#
#   bundle exec ruby scripts/generate_stage_cases.rb --out DIR \
#     [--boundary raw-tree|typed-model] [--engines native,ruby] \
#     [--producer FILE] [CORPUS.yml ...]
#
# With no corpus files it reads every corpora/*.yml. --producer writes the
# producer block for the generation's provenance.yaml (repository, commit,
# generator and input checksums, environment); it needs a clean checkout.
# The output is deterministic: same commit, same bytes.

require "digest"
require "fileutils"
require "json"
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
  BOUNDARIES = %w[raw-tree typed-model].freeze
  LML = "model/asciimath.lml.json"

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

  # The internal raw tree (Amath::Parser.raw, the legacy-shaped tree the
  # normalized grammar's tree unwraps to); Amath.parse_model returns the model.
  def parse(input, engine)
    tree = Amath::Parser.raw(input, decimal: DECIMAL, engine: engine)
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

  # Tagged typed-model node of +klass+ from its bound data +data+ (a Hash
  # of attribute name => plain data).
  def model_node(klass, data, path)
    raise "#{path}: #{klass} data is a #{data.class}, not a Hash" unless data.is_a?(Hash)

    attributes = klass.attributes
    unknown = data.keys.map(&:to_s) - attributes.keys.map(&:to_s)
    raise "#{path}: #{klass} has no attribute #{unknown.join(', ')}" unless unknown.empty?

    instance = nil
    fields = attributes.filter_map do |name, attribute|
      # Symbol derivation belongs to the stage, not to a non-portable LML
      # attribute option. Keep the bound-data producer equal to the live model.
      symbol_field = klass.include?(Amath::Model::Spelled) && %i[value kind].include?(name)
      value = if attribute.derived? || symbol_field
                (instance ||= klass.new(data)).public_send(name)
              else
                data.fetch(name.to_s) { data[name] }
              end
      next if value.nil?

      [name.to_s, model_field(attribute, value, "#{path}/#{name}")]
    end
    { "node" => klass.name, "fields" => fields }
  end

  def model_field(attribute, value, path)
    return model_value(attribute.type, value, path) unless attribute.collection?
    raise "#{path}: a collection holds a #{value.class}" unless value.is_a?(Array)

    { "array" => value.each_with_index.map { |item, i| model_value(attribute.type, item, "#{path}/#{i}") } }
  end

  def model_value(type, value, path)
    if type.is_a?(Class) && type < Lutaml::Model::Serializable
      model_node(type, value, path)
    elsif type == Lutaml::Model::Type::String && value.is_a?(String)
      string(value)
    else
      raise "#{path}: #{value.class} for a #{type} attribute"
    end
  end

  # The same tagged form read from a built model, through its declared
  # attributes (never lutaml-model serialization).
  def model_walk(value)
    case value
    when Lutaml::Model::Serializable
      fields = value.class.attributes.filter_map do |name, _attribute|
        child = value.public_send(name)
        [name.to_s, model_walk(child)] unless child.nil?
      end
      { "node" => value.class.name, "fields" => fields }
    when Array then { "array" => value.map { |item| model_walk(item) } }
    when String then string(value)
    else raise ArgumentError, "unexpected #{value.class} in the model"
    end
  end

  # [tagged Document from the bound data, the built Document] of +input+.
  def model(input, engine)
    entry, text, tree = Amath::Parser.run(input, decimal: DECIMAL, engine: engine)
    raise "#{input.inspect}: ran on #{Amath.last_engine}, not #{engine}" unless Amath.last_engine == engine

    data = { "decimal" => DECIMAL }
    data["expression"] = Amath.bindings.apply(entry, tree).fetch(:expression) unless text.empty?
    document = Amath.parse_model(input, decimal: DECIMAL, engine: engine)
    [model_node(Amath::Model::Document, data, "/"), document]
  end

  def expected_model(entry, engines)
    id = entry.fetch("id")
    input = entry.fetch("input")
    expected(entry, engines)
    results = engines.map { |engine| model(input, engine) }
    dumps = results.map(&:first)
    raise "#{id}: the engines return different models" if dumps.uniq.size > 1

    results.each do |dump, document|
      raise "#{id}: the built model differs from its bound data" unless model_walk(document) == dump
    end
    { "preprocessed" => string(input), "tree" => dumps.first }
  end

  def payload(path, engines, boundary = "raw-tree")
    corpus = YAML.safe_load_file(path)
    unless corpus["schema_version"] == 1
      raise "#{path}: schema_version is not 1"
    end

    return model_payload(corpus, File.basename(path, ".yml"), engines) if boundary == "typed-model"

    group = File.basename(path, ".yml")
    cases = corpus.fetch("cases").map do |entry|
      { "id" => "#{group}.#{entry.fetch('id')}",
        "input" => string(entry.fetch("input")),
        "options" => { "decimal" => DECIMAL },
        "expected" => expected(entry, engines) }
    end
    { "schema" => SCHEMA, "group" => group,
      "description" => "amath raw trees for corpora/#{group}.yml " \
                       "(#{corpus.fetch('issue')}). Amath.parse_model has no " \
                       "preprocessing, so preprocessed is the input.",
      "boundary" => "raw-tree", "cases" => cases }
  end

  def model_payload(corpus, source, engines)
    cases = corpus.fetch("cases").map do |entry|
      { "id" => "#{source}.#{entry.fetch('id')}.model",
        "input" => string(entry.fetch("input")),
        "options" => { "decimal" => DECIMAL },
        "expected" => expected_model(entry, engines) }
    end
    { "schema" => SCHEMA, "group" => "model-#{source}",
      "description" => "amath typed models (Amath.parse_model) for corpora/#{source}.yml " \
                       "(#{corpus.fetch('issue')}). Each object is its model class " \
                       "(#{LML}) with its set fields in declaration order; nil " \
                       "fields are left out. Amath.parse_model has no preprocessing, so " \
                       "preprocessed is the input.",
      "boundary" => "typed-model", "cases" => cases }
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

  # The committed LML export of the model classes the typed-model rows name.
  def lml(commit)
    export = JSON.parse(File.read(File.join(ROOT, LML)))
    { "format" => export.fetch("format"),
      "checksum" => "sha256:#{Digest::SHA256.file(File.join(ROOT, LML)).hexdigest}",
      "models" => export.fetch("models").size,
      "export" => tracked(LML, commit) }
  end

  def environment(commit, boundary = "raw-tree")
    sums = checksums
    model = boundary == "typed-model"
    dependencies = { "parsanol" => Parsanol::VERSION }
    dependencies["lutaml-model"] = Lutaml::Model::VERSION if model
    { "ruby" => { "engine" => RUBY_ENGINE, "version" => RUBY_VERSION },
      "xml_engine" => nil,
      "lockfile" => lockfile,
      "dependencies" => dependencies,
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
      "lml" => (lml(commit) if model) }
  end

  def producer(corpora, engines, boundary = "raw-tree")
    clean = git("status", "--porcelain").empty?
    raise "--producer needs a clean checkout" unless clean

    model = boundary == "typed-model"
    commit = git("rev-parse", "HEAD").strip
    inputs = corpora.map { |path| path.delete_prefix("#{ROOT}/") } +
      ["artifacts/asciimath.json"]
    inputs << LML if model
    { "kind" => "stage-gem", "repository" => REPOSITORY, "commit" => commit,
      "version" => Amath::VERSION,
      "generator" => tracked("scripts/generate_stage_cases.rb", commit),
      "inputs" => inputs.map { |relative| tracked(relative, commit) },
      "environment" => environment(commit, boundary),
      "semantic_boundary" => boundary,
      "configuration" => { "decimal" => DECIMAL,
                           "engines" => engines.map(&:to_s),
                           "entry_point" => model ? "Amath.parse_model" : "Amath::Parser.raw" } }
  end

  def options(argv)
    opts = { engines: ENGINES, corpora: [], boundary: "raw-tree" }
    args = argv.dup
    until args.empty?
      case (arg = args.shift)
      when "--out" then opts[:out] = File.expand_path(args.shift)
      when "--producer" then opts[:producer] = File.expand_path(args.shift)
      when "--engines" then opts[:engines] = args.shift.split(",").map(&:to_sym)
      when "--boundary" then opts[:boundary] = args.shift
      when /\A--/ then abort "unknown option #{arg.inspect}"
      else opts[:corpora] << File.expand_path(arg)
      end
    end
    opts
  end

  def check(opts)
    unless opts[:out]
      abort "usage: #{$PROGRAM_NAME} --out DIR [--boundary raw-tree|typed-model] " \
            "[--engines native,ruby] [--producer FILE] [CORPUS.yml ...]"
    end
    unless BOUNDARIES.include?(opts[:boundary])
      abort "unknown boundary #{opts[:boundary].inspect} (#{BOUNDARIES.join(', ')})"
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
    payloads = opts[:corpora].map { |path| payload(path, opts[:engines], opts[:boundary]) }
    block = (producer(opts[:corpora], opts[:engines], opts[:boundary]) if opts[:producer])
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
