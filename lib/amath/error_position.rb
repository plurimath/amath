# frozen_string_literal: true

module Amath
  # Where a rejected input failed, reported the way Plurimath's Parslet
  # parser did.
  module ErrorPosition
    module_function

    # The zero-based byte offset of the rejection +failure+ (a
    # Parsanol::ParseFailed for +text+ from +entry+), or nil if none is known.
    def byte_offset(failure, artifact, entry, text)
      parslet_position(artifact, entry,
                       text) || deepest_position(failure.parse_failure_cause)
    end

    # The character offset of byte offset +byte+ in +text+.
    def char_offset(text, byte)
      text.byteslice(0, byte).force_encoding(Encoding::UTF_8).scrub.length
    end

    # The rejection position Plurimath's Parslet parser reported: the
    # deepest *leaf* of the cause tree built by a Parslet-style Tree
    # reporter, which holds only the failures that caused the final
    # rejection. Neither engine's own cause gives this: the native engine
    # returns one childless cause at its farthest failure, and the Ruby
    # engine's Deepest reporter grafts in failures from branches that
    # later succeeded, so both can point past Parslet's position. The
    # interpreter reparse runs only on rejection. Returns nil if that
    # reparse unexpectedly accepts, so the caller falls back.
    #
    # The interpreter and deepest_leaf recurse once per nesting level; if
    # that exhausts the stack on very deep input, this returns nil too.
    def parslet_position(artifact, entry, text)
      cause = begin
        artifact.root_atom(entry).parse(text, reporter: Parsanol::ErrorReporter::Tree.new)
        nil
      rescue Parsanol::ParseFailed => e
        e.parse_failure_cause
      end
      cause && deepest_leaf(cause)
    rescue SystemStackError
      nil
    end

    # Parslet's rule: a node with children reports no position of its own.
    def deepest_leaf(cause)
      children = cause.children.compact
      return cause.position if children.empty?

      children.filter_map { |c| deepest_leaf(c) }.max
    end

    # Iterative: the cause tree of a deeply nested input is as deep as the
    # input, so recursion here could exhaust the stack.
    def deepest_position(cause)
      deepest = nil
      stack = [cause].compact
      until stack.empty?
        node = stack.pop
        deepest = node.position if node.position && (deepest.nil? || node.position > deepest)
        stack.concat(node.children.compact)
      end
      deepest
    end

    private_class_method :parslet_position, :deepest_leaf, :deepest_position
  end
end
