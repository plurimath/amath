# frozen_string_literal: true

# data/quantities.json: the unitsdb quantities that the pma quantity
# assertion `unit(J::energy)` names (plurimath docs/pma.adoc "Quantity
# assertion"), as a map from each English quantity name to the unitsml
# identifier of the quantity (`energy` -> `q:energy`). Read by
# Amath::Pma at runtime, so amath needs no runtime dependency on unitsdb.
#
# The map is a pure function of the unitsdb gem the Gemfile pins. The file
# records that gem's version and the sha256 of the serialized map.
#
# Usage:
#   bundle exec ruby scripts/quantities.rb            write the file
#   bundle exec ruby scripts/quantities.rb --check    exit 1 if the file is
#     not what the pinned unitsdb gives, or if its sha256 does not match
#     its map

require "digest"
require "json"
require "yaml"

module Quantities
  FORMAT = "amath-quantities/v1"
  PATH = File.expand_path("../data/quantities.json", __dir__)

  module_function

  # [map, unitsdb version] from the installed unitsdb gem.
  def from_unitsdb
    spec = Gem::Specification.find_by_name("unitsdb")
    doc = YAML.safe_load_file(File.join(spec.gem_dir, "data/quantities.yaml"), aliases: true)
    [map(doc.fetch("quantities")), spec.version.to_s]
  end

  # English name => unitsml id, sorted by name. A name that two quantities
  # share, or a quantity without a unitsml identifier, stops the export.
  def map(quantities)
    out = {}
    quantities.each do |q|
      id = Array(q["identifiers"]).find { |i| i["type"] == "unitsml" }&.fetch("id")
      abort "unitsdb quantity without a unitsml identifier: #{q['short'].inspect}" unless id

      Array(q["names"]).select { |n| n["lang"] == "en" }.map { |n| n["value"] }.uniq.each do |name|
        abort "unitsdb quantity name #{name.inspect} is used by #{out[name]} and #{id}" if out.key?(name) && out[name] != id

        out[name] = id
      end
    end
    out.sort.to_h
  end

  def document(map, version)
    { "format" => FORMAT, "unitsdb" => version, "sha256" => digest(map), "quantities" => map }
  end

  def digest(map)
    "sha256:#{Digest::SHA256.hexdigest(JSON.generate(map))}"
  end

  def serialize(doc)
    "#{JSON.pretty_generate(doc)}\n"
  end
end

if $PROGRAM_NAME == __FILE__
  check = ARGV.delete("--check")
  abort "usage: ruby scripts/quantities.rb [--check]" unless ARGV.empty?

  map, version = Quantities.from_unitsdb
  fresh = Quantities.serialize(Quantities.document(map, version))
  if check
    abort "#{Quantities::PATH} is missing" unless File.exist?(Quantities::PATH)

    committed = File.read(Quantities::PATH)
    doc = JSON.parse(committed)
    abort "#{Quantities::PATH}: sha256 does not match its quantities" unless doc["sha256"] == Quantities.digest(doc["quantities"])
    unless committed == fresh
      abort "#{Quantities::PATH} is stale against unitsdb #{version} (it records #{doc['unitsdb']}); " \
            "run ruby scripts/quantities.rb"
    end
    puts "quantities: #{map.size} names from unitsdb #{version}, current"
  else
    File.write(Quantities::PATH, fresh)
    puts "wrote #{Quantities::PATH}: #{map.size} names from unitsdb #{version}"
  end
end
