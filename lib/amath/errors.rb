# frozen_string_literal: true

module Amath
  # Base class for every error Amath raises on purpose.
  class Error < StandardError; end

  # The input is not valid AsciiMath for the selected decimal marker.
  #
  # Positions are zero-based and match what Plurimath's Parslet parser
  # reported, on either engine: the deepest leaf of the tree of failures
  # that caused the rejection. +byte_offset+ counts UTF-8 bytes into the
  # input (Parsanol's native unit); +char_offset+ counts characters, the
  # unit Parslet used.
  class ParseError < Error
    attr_reader :input, :byte_offset, :char_offset

    def initialize(message, input:, byte_offset:, char_offset:)
      super(message)
      @input = input
      @byte_offset = byte_offset
      @char_offset = char_offset
    end
  end

  # The input nests deeper than the engine that ran can handle: the native
  # engine's recursion limit under +engine: :native+, or an exhausted Ruby
  # stack. A ParseError so existing rescues keep working; the offsets are
  # nil because no rejection position exists.
  class NestingTooDeep < ParseError; end

  # The compiled grammar artifact is missing, unreadable, malformed, fails
  # its checksum, declares an unsupported shape, or cannot be compiled by the
  # installed Parsanol. Amath never falls back to another grammar.
  class ArtifactError < Error; end

  # +engine: :native+ was requested but Parsanol's native extension is not
  # available on this platform.
  class EngineUnavailable < Error; end
end
