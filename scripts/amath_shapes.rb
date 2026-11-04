# frozen_string_literal: true

require "set"
require_relative "normalize_shapes"

# amath's additions to the shared capture-shape normalization
# (scripts/normalize_shapes.rb, byte-identical to the shared rules N1-N7 of
# the other stage gems). Read by scripts/generate_grammar.rb and
# scripts/generate_model.rb.
#
#   N8 empty run          a text run (a repetition of min 0 whose elements
#                         are text) in a node slot at a named position, where
#                         legacy holds [] when it matched nothing, becomes
#                         `(1*(x)) as literal / "" as empty_list`
#   N9 catalog spelling   text captured under a catalog capture name (one
#                         the legacy transform resolves through its symbol
#                         catalog) becomes `((x) as spelling) as name`, so
#                         the model can type it as a catalog symbol
#
# Corrections to the shared rules, needed by the AsciiMath grammar and
# without effect on unicodemath's (F0's normalized rules and capture shapes
# are unchanged under them):
#
#   - a nested capture of the same name (`((sequence) as power_base x) as
#     power_base`) keeps its keys: the shared #shape loses them, because
#     `@captures[name] |= shape(...)` reads the old value first;
#   - a repetition captured under a name that also holds a node elsewhere
#     is a list in a node slot (N3), not a list slot (N4);
#   - a rule forced from a named position (N6) is normalized as named, so
#     N8 applies to it;
#   - two constant wrappers (`empty`, `present`) in one sequence are no
#     collision (merging them loses nothing).
class AmathShapes < ShapeNormalizer
  EXTRA_WRAPPERS = {
    "empty_list" => "empty list: legacy produced [] (a text run that matched nothing)",
    "spelling" => "text: the catalog spelling, as legacy captured it",
  }.freeze

  # Wrappers whose value is always "" and whose legacy value is a
  # constant ("" or nil): two of them merging into one key lose nothing.
  CONSTANT_WRAPPERS = %w[empty present].freeze

  # +catalog+: capture names whose text is a catalog spelling (N9).
  def initialize(rules, normalized: false, catalog: [])
    @catalog = catalog.to_set
    super(rules, normalized: normalized)
  end

  def run
    spell unless @catalog.empty?
    super
  end

  def wrapper?(key) = super || EXTRA_WRAPPERS.key?(key)

  def shape(node, named)
    if node.key?("alt") then node["alt"].map { |n| shape(n, named) }.reduce(:|)
    elsif node.key?("seq") then sequence(node["seq"].map { |n| shape(n, false) })
    elsif node.key?("as")
      # The inner shape first: it may record a nested capture of the same
      # name, which `@captures[name] |= shape(...)` would overwrite.
      inner = shape(node["of"], true)
      @captures[node["as"]] |= inner
      Shape.of(:hash, [node["as"]])
    elsif node.key?("ref") then @rule_shapes[[node["ref"], named]]
    elsif node.key?("rep") then repetition(node, named)
    elsif node.key?("look") then NIL
    elsif node.key?("str") || node.key?("re") || node.key?("decimal_marker") then STRING
    else raise "unknown grammar node #{node.keys.inspect}"
    end
  end

  # Sequences where two parts can carry the same wrapper key (a merge
  # would drop one part's text). Empty after a sound #run.
  def collisions
    solve
    found = []
    walk = lambda do |n, rule|
      k = n.keys.first
      if k == "seq"
        seen = Hash.new(0)
        n["seq"].each do |c|
          shape(c, false).hash_keys.each { |key| seen[key] += 1 if wrapper?(key) && !CONSTANT_WRAPPERS.include?(key) }
        end
        found << "#{rule}: #{seen.select { |_, v| v > 1 }.keys.join(',')}" if seen.any? { |_, v| v > 1 }
      end
      case k
      when "seq", "alt" then n[k].each { |c| walk.call(c, rule) }
      when "rep", "look" then walk.call(n[k], rule)
      when "as" then walk.call(n["of"], rule)
      end
    end
    @rules.each { |r, b| walk.call(b, r) }
    found
  end

  # Wrapper capture names the rewritten rules use, with their kind.
  def wrapper_list
    used = capture_names(@rules).select { |k| wrapper?(k) }.sort
    used.to_h do |k|
      [k, { "list" => "list", "empty" => "empty", "present" => "nil", "empty_list" => "empty_list" }.fetch(k, "text")]
    end
  end

  private

  # N9: every catalog capture whose value is text (or optional text) gets
  # its text under +spelling+. Runs once, before the shape rules.
  def spell
    solve
    @rules.each_key do |name|
      @current = name
      @rules[name] = spell_node(@rules[name])
    end
  end

  def spell_node(node)
    k = node.keys.first
    case k
    when "seq", "alt" then { k => node[k].map { |c| spell_node(c) } }
    when "rep", "look" then node.merge(k => spell_node(node[k]))
    when "as"
      inner = spell_node(node["of"])
      if @catalog.include?(node["as"])
        target = inner["tag"] == "maybe" ? inner["rep"] : inner
        if shape(target, true).solid == Set[:string]
          count("N9 catalog spelling")
          spelled = { "as" => "spelling", "of" => target }
          inner = inner["tag"] == "maybe" ? inner.merge("rep" => spelled) : spelled
        end
      end
      { "as" => node["as"], "of" => inner }
    else node
    end
  end

  # A capture whose value is a repetition (N4) stays a list, unless the
  # capture also holds a node elsewhere (then the repetition is a list in
  # a node slot, N3). A run of text (no element is ever a node) is text,
  # not a list (N8).
  def list_slot?(name, inner)
    solid = @captures[name].solid
    inner.key?("rep") && inner["tag"] != "maybe" && solid.include?(:array) && !solid.include?(:hash) &&
      !text_run?(inner)
  end

  def text_run?(rep)
    rep["min"].zero? && shape(rep["rep"], false).kinds.subset?(Set[:string, :nil])
  end

  # +node+ rewritten so that its value is always a hash (or nil).
  def force_hash(node, named)
    s = shape(node, named)
    return node if s.solid.subset?(Set[:hash])
    return wrap(node, "literal", "N1 text alternative", named) if s.solid.subset?(Set[:string])

    case node.keys.first
    when "alt" then { "alt" => node["alt"].map { |c| force_hash(c, named) } }
    when "ref" then force_ref(node, s, named)
    when "seq" then force_seq(node)
    when "rep"
      if node["tag"] == "maybe"
        raise "N2 at a named position in #{@current}" if named

        count("N2 empty alternative")
        { "alt" => [force_hash(node["rep"], false), { "as" => "empty", "of" => { "str" => "" } }] }
      elsif text_run?(node)
        count("N8 empty run")
        { "alt" => [{ "as" => "literal", "of" => node.merge("min" => 1) }, { "as" => "empty_list", "of" => { "str" => "" } }] }
      elsif node["min"].zero?
        raise "list of min 0 in a node slot (#{@current}); not handled"
      else
        wrap(node.merge("rep" => force_hash(node["rep"], false)), "list", "N3 list in node slot")
      end
    else raise "cannot normalize #{node.keys.first} in #{@current}"
    end
  end

  def force_ref(node, s, named)
    return wrap(node, "list", "N3 list in node slot") if s.solid == Set[:array]

    name = node["ref"]
    unless @forced_rules.include?(name)
      @forced_rules << name
      count("N6 forced rule")
      saved = @current
      @current = name
      @rules[name] = force_hash(@rules[name], named)
      @current = saved
    end
    node
  end

  # A text wrapper around an optional part would hold nil (or []) when the
  # part is absent, so `[x] as w` is written `x as w / "" as empty` and
  # `0*n(x) as w` is written `1*n(x) as w / "" as empty` (same language).
  # At a named position (+named+) legacy holds [] for an unmatched
  # repetition, so the absent alternative is `"" as empty_list` (N8).
  def wrap(node, name, rule, named = false)
    count(rule)
    opt = optional(node)
    if name != "list" && opt
      raise "an optional at a named position in #{@current}; not handled" if named && opt["tag"] == "maybe"

      absent = named ? "empty_list" : "empty"
      count(named ? "N8 empty run" : "N2 empty alternative")
      present = opt["tag"] == "maybe" ? opt["rep"] : opt.merge("min" => 1)
      return { "alt" => [{ "as" => name, "of" => present }, { "as" => absent, "of" => { "str" => "" } }] }
    end
    { "as" => name, "of" => node }
  end
end
