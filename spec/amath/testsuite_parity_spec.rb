# frozen_string_literal: true

require "yaml"
require_relative "../../scripts/generate_stage_cases"

# Raw-tree parity with the plurimath-testsuite asciimath stage rows: the
# internal raw tree (the normalized grammar's tree, unwrapped and renested)
# equals each row's oracle tree, and Amath.parse builds the typed model of
# every row. Runs when AMATH_TESTSUITE names a plurimath-testsuite checkout
# (CI checks out the generation the test workflow pins).
RSpec.describe "plurimath-testsuite asciimath parity" do
  root = ENV.fetch("AMATH_TESTSUITE", nil)
  generation = File.join(root.to_s, "stages/asciimath/generations/000002/payloads")

  def self.rows(dir)
    Dir[File.join(dir, "*.yaml")].sort.flat_map do |file|
      YAML.safe_load_file(file, aliases: true).fetch("cases").map do |c|
        input = c["input"].is_a?(Hash) ? c["input"].fetch("str") : c["input"]
        { id: "#{File.basename(file, '.yaml')}/#{c['id']}", input: input,
          decimal: c.dig("options", "decimal") || ".",
          parse_tree: c["parse_tree"], tagged: c.dig("expected", "tree") }
      end
    end
  end

  def texts(value)
    case value
    when Hash then value.to_h { |k, v| [k.to_s, texts(v)] }
    when Array then value.map { |v| texts(v) }
    when nil then nil
    else value.to_s
    end
  end

  before(:all) do
    skip "set AMATH_TESTSUITE to a plurimath-testsuite checkout" unless root && File.directory?(generation)
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
    @artifact = Amath.artifact
    @bindings = Amath.bindings
  end

  before do
    Amath.artifact_path = Amath::DEFAULT_ARTIFACT_PATH
    allow(Amath).to receive_messages(artifact: @artifact, bindings: @bindings)
  end

  %i[native ruby].each do |engine|
    it "matches every generation-2 oracle tree and builds every model on #{engine}" do
      require_native! if engine == :native
      rows = self.class.rows(generation)
      expect(rows.size).to eq(183)
      failures = rows.filter_map do |row|
        next if row[:parse_tree].nil? && row[:tagged].nil?

        tree = Amath::Parser.raw(row[:input], decimal: row[:decimal], engine: engine)
        ok = row[:tagged] ? StageCases.tagged(tree, row[:input]) == row[:tagged] : texts(tree) == row[:parse_tree]
        doc = Amath.parse(row[:input], decimal: row[:decimal], engine: engine)
        ok &&= doc.is_a?(Amath::Model::Document) && (row[:input].empty? || doc.expression)
        row[:id] unless ok
      end
      expect(failures).to eq([])
    end
  end
end
