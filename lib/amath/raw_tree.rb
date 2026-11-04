# frozen_string_literal: true

require "json"

module Amath
  # The internal raw-tree boundary: the parse tree of the legacy Plurimath
  # AsciiMath grammar, rebuilt from the tree of amath's normalized grammar.
  #
  # The grammar generator (scripts/generate_grammar.rb) normalizes capture
  # shapes by only ADDING captures, listed in grammars/asciimath.wrappers.json
  # as {name => kind}. RawTree.legacy removes them again and renests the
  # flat expression chains (Renester), so the result is exactly the legacy
  # tree. It is not public API: the stage-case generator and the parity
  # specs read it; Amath.parse returns the typed model.
  #
  # Unwrapping replaces each wrapper by the value legacy produced there and
  # re-runs Parslet's flattening algebra (Parsanol::Atoms::CanFlatten
  # merge_fold / flatten_repetition) over the parts, bottom-up:
  #
  #   hash   entries are split, in order, into runs of ordinary keys (one
  #          hash part each) and wrapper keys (one part each, by kind):
  #            text        -> the wrapped value (nil / [] -> "")
  #            empty       -> "" (String)
  #            empty_list  -> []
  #            list        -> the list ([] -> "")
  #            nil         -> nil
  #          then folded with merge_fold, as legacy folded the sequence.
  #          A hash of nil-kind wrappers only is nil.
  #   array  elements are unwrapped, then flatten_repetition (named).
  #
  # The walk recurses once per tree level; the grammar bounds that depth
  # (long sums are flat chains, see Renester).
  module RawTree
    extend Parsanol::Atoms::CanFlatten

    WRAPPERS_PATH = File.expand_path("../../grammars/asciimath.wrappers.json", __dir__)

    module_function

    # The legacy tree of one +raw+ parse result (the entry rule's tree,
    # with its `root` capture).
    def legacy(raw, wrappers = self.wrappers)
      Renester.call(unwrap(Parser.unwrap_root(raw), wrappers))
    end

    # {wrapper name => kind}, from grammars/asciimath.wrappers.json.
    def wrappers
      @wrappers ||= JSON.parse(File.read(WRAPPERS_PATH)).fetch("wrappers").freeze
    end

    def unwrap(value, wrappers = self.wrappers)
      case value
      when Hash then unwrap_hash(value, wrappers)
      when Array then RawTree.send(:flatten_repetition, value.map { |v| unwrap(v, wrappers) }, true)
      else value
      end
    end

    def unwrap_hash(value, wrappers)
      return value.to_h { |k, v| [k, unwrap(v, wrappers)] } if value.keys.none? { |k| wrappers.key?(k.to_s) }

      parts = []
      run = nil
      only_nil = true
      value.each do |k, v|
        kind = wrappers[k.to_s]
        if kind
          parts << run if run
          run = nil
          only_nil &&= kind == "nil"
          parts << part(kind, unwrap(v, wrappers))
        else
          only_nil = false
          (run ||= {})[k] = unwrap(v, wrappers)
        end
      end
      parts << run if run
      return nil if only_nil

      RawTree.send(:foldl, parts) { |l, r| RawTree.send(:merge_fold, l, r) }
    end

    def part(kind, value)
      case kind
      when "text" then value.nil? || value == [] ? +"" : value
      when "empty" then +""
      when "empty_list" then []
      when "list" then value == [] ? +"" : value
      when "nil" then nil
      else raise ArgumentError, "unknown wrapper kind #{kind}"
      end
    end

    private_class_method :unwrap_hash, :part
  end
end
