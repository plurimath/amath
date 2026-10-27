# frozen_string_literal: true

module Amath
  # Rebuilds the nested tree of a flattened expression chain.
  #
  # The grammar parses a run of terms (a sum, a sequence) as a repetition
  # instead of right recursion, so the engines need no stack depth
  # proportional to the number of terms. It returns such a run as
  #
  #   {expr: {amath_chain: [{amath_step: part_1}, {amath_lr: part_2}, ...,
  #                         {amath_step: part_n}, {amath_end: rest}]}}
  #
  # (the +amath_end+ item is optional), where the recursive rule returned
  #
  #   {expr: part_1 + {left_right: part_2 + ... {expr: part_n + rest}}}
  #
  # with + the parser's merge of sequence results: each +amath_step+ part
  # becomes an :expr level and each +amath_lr+ part a :left_right level.
  # The grammar already puts the chain node under its outermost level's
  # key (:expr above), so sibling merges see the oracle's keys.
  # Renester.call replaces every chain node with the value of that
  # outermost level. It
  # never recurses, so trees of any depth are safe. Every Hash and Array
  # of the result is new; leaves are shared with the input tree.
  module Renester
    CHAIN = :amath_chain
    FINAL = :amath_end
    # Chain item key => key of the level it becomes.
    LEVELS = { amath_step: :expr, amath_lr: :left_right }.freeze

    module_function

    # +tree+ with every chain node rebuilt.
    def call(tree)
      return tree unless container?(tree)

      done = []
      todo = [[tree, false]]
      step(todo, done, *todo.pop) until todo.empty?
      done.first
    end

    # One move of the post-order walk: a leaf is done; a container is
    # rebuilt once its children are done, after queueing them first.
    def step(todo, done, node, children_done)
      if !container?(node)
        done << node
      elsif children_done
        done << rebuild(node, done.pop(node.size))
      else
        todo << [node, true]
        children = node.is_a?(Hash) ? node.values : node
        children.reverse_each { |child| todo << [child, false] }
      end
    end

    def container?(node)
      node.instance_of?(Hash) || node.instance_of?(Array)
    end

    # A chain node ({amath_chain: items}, always alone in its Hash) becomes
    # the value of its outermost level; any other container gets +values+
    # (already rebuilt).
    def rebuild(node, values)
      return values unless node.is_a?(Hash)
      return renest(values.first).each_value.first if node.key?(CHAIN)

      node.keys.zip(values).to_h
    end

    # The nested tree of a chain's items, built from the innermost level
    # outwards.
    def renest(items)
      last = items.last
      rest = last.instance_of?(Hash) && last.key?(FINAL) ? last[FINAL] : ""
      tree = rest
      items.reverse_each do |item|
        item.each do |key, part|
          level = LEVELS[key]
          tree = { level => fold(part, tree) } if level
        end
      end
      tree
    end

    # Parsanol's result of a sequence whose (flattened) elements are +left+
    # and +right+: nil elements are skipped, all nil is "", otherwise the
    # two are merged.
    def fold(left, right)
      return right.nil? ? "" : right if left.nil?
      return left if right.nil?

      merge(left, right)
    end

    # Parsanol::Atoms::CanFlatten#merge_fold, without its duplicate-key
    # warning.
    def merge(left, right)
      if left.instance_of?(right.class)
        left.is_a?(Hash) ? left.merge(right) : left + right
      elsif text?(left) || text?(right)
        merge_text(left, right)
      else
        merge_list(left, right)
      end
    end

    # A Hash and an Array: the Hash joins the Array.
    def merge_list(left, right)
      return left + [right] if right.instance_of?(Hash)
      return [left] + right if left.instance_of?(Hash)

      raise Error, "cannot merge #{left.class} with #{right.class}"
    end

    # At least one side is text: the other side wins over text, and a
    # Slice wins over a String.
    def merge_text(left, right)
      return left unless text?(left)
      return right unless text?(right)

      right.instance_of?(Parsanol::Slice) ? right : left
    end

    def text?(value)
      value.instance_of?(String) || value.instance_of?(Parsanol::Slice)
    end

    private_class_method :step, :container?, :rebuild,
                         :renest, :fold, :merge, :merge_text, :merge_list,
                         :text?
  end
end
