# frozen_string_literal: true

# The build-time reserved-word collision check (amath#16 task 2, plurimath
# docs/pma.adoc "The registry v2 contract", item 5). Fails when a reserved
# word of the pma grammar (the registry's "reserved_words") is also
#
#   - a spelling of any registry entry, of either dialect, or
#   - a unit symbol or unit name in unitsdb (data/units.yaml of the unitsdb
#     gem: every symbol's ascii, unicode and id form, every name, and the
#     short name).
#
# Matching is exact and also case-insensitive, so `Unit` or `DIFF` count.
#
# Usage: bundle exec ruby scripts/check_reserved_words.rb [UNITS_YAML]

require "yaml"
require_relative "registry"

module ReservedWords
  module_function

  # [[reserved word, source, colliding text], ...]
  def collisions(reserved, sources)
    reserved.flat_map do |word|
      sources.flat_map do |source, texts|
        texts.select { |t| t.casecmp?(word) }.map { |t| [word, source, t] }
      end
    end
  end

  # unitsdb unit symbols and names from a units.yaml document.
  def unitsdb_texts(units)
    units.fetch("units").flat_map do |unit|
      names = Array(unit["names"]).map { |n| n["value"] } + [unit["short"]]
      symbols = Array(unit["symbols"]).flat_map { |s| s.values_at("ascii", "unicode", "id") }
      (names + symbols).compact.map(&:to_s)
    end.uniq
  end

  def default_units_yaml
    spec = Gem::Specification.find_by_name("unitsdb")
    [File.join(spec.gem_dir, "data/units.yaml"), spec.version.to_s]
  end
end

if $PROGRAM_NAME == __FILE__
  path, version = ARGV.empty? ? ReservedWords.default_units_yaml : [ARGV.first, "file"]
  registry = Registry.load
  reserved = registry.fetch("reserved_words")
  units = ReservedWords.unitsdb_texts(YAML.safe_load_file(path, aliases: true))
  sources = { "registry" => Registry.spellings(registry), "unitsdb" => units }
  found = ReservedWords.collisions(reserved, sources)
  unless found.empty?
    found.each { |word, source, text| warn "COLLISION: reserved word #{word.inspect} is #{source} #{text.inspect}" }
    abort "reserved-word collision check FAILED (#{found.size})"
  end
  puts "reserved-word collision check: #{reserved.join(' ')} vs #{sources['registry'].size} registry " \
       "spellings and #{units.size} unitsdb #{version} unit symbols/names: 0 collisions"
end
