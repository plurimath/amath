# frozen_string_literal: true

require "json"
require "parsanol"
require_relative "amath/version"
require_relative "amath/errors"

# AsciiMath parser backed by a compiled Parsanol (PARG) grammar artifact.
#
# See docs/parser-contract.adoc for the full contract.
module Amath
  # Decimal marker => artifact entry name.
  DECIMAL_ENTRIES = {
    "." => "dot",
    "," => "comma",
    "٫" => "arabic", # ARABIC DECIMAL SEPARATOR
  }.freeze

  ENGINES = %i[auto native ruby].freeze

  # Deepest bracket nesting sent to the native engine off the main thread.
  THREAD_NATIVE_DEPTH = 25
  OPENING = "([{\u2112\u1455".chars.freeze
  CLOSING = ")]}\u211b\u1450".chars.freeze

  DEFAULT_ARTIFACT_PATH = File.expand_path("../artifacts/asciimath.json", __dir__)

  @artifact_path = DEFAULT_ARTIFACT_PATH
  @artifact = nil
  @lock = Mutex.new

  # Raised inside Parsanol's native error path when the native engine hit its
  # recursion limit, before Parsanol's own interpreter reparse runs (that
  # reparse can take minutes or exhaust the Ruby stack on deep input).
  class NativeRecursionLimit < Error; end
  private_constant :NativeRecursionLimit

  # Parsanol::Native.raise_native_parse_error translates a native failure.
  # For a recursion-limit failure (which carries no position) it reparses
  # through the Ruby interpreter with a Deepest reporter. While amath's own
  # native call is running on this thread, this hook turns that failure into
  # NativeRecursionLimit instead; every other failure, and every other
  # caller of Parsanol, is unaffected.
  module NativeRecursionGuard
    MESSAGE = /\A(?:Maximum recursion depth \(\d+\) exceeded|Recursion limit exceeded\b)/
    KEY = :amath_native_recursion_guard

    def self.watch
      outer = Thread.current[KEY]
      Thread.current[KEY] = true
      yield
    ensure
      Thread.current[KEY] = outer
    end

    def self.installed?
      Parsanol::Native.singleton_class.ancestors.include?(self)
    end

    def raise_native_parse_error(error, grammar, input)
      if Thread.current[KEY] && error.message.match?(MESSAGE)
        raise NativeRecursionLimit, error.message.lines.first.strip, cause: nil
      end

      super
    end
  end

  if Parsanol::Native.singleton_class.method_defined?(:raise_native_parse_error)
    Parsanol::Native.singleton_class.prepend(NativeRecursionGuard)
  end

  class << self
    # Parse +input+ and return the Parsanol tree (Hash/Array of
    # Parsanol::Slice leaves, or a plain "" for empty input).
    #
    # The engine that ran is available afterwards from Amath.last_engine.
    def parse(input, decimal: ".", engine: :auto)
      entry = DECIMAL_ENTRIES.fetch(decimal) do
        raise ArgumentError,
              "unsupported decimal marker #{decimal.inspect} " \
              "(supported: #{DECIMAL_ENTRIES.keys.map(&:inspect).join(', ')})"
      end
      text = normalize_input(input)
      mode = resolve_engine(engine)
      tree, ran = run_engine(artifact, entry, text, mode, fallback: engine == :auto)
      Thread.current[:amath_last_engine] = ran
      tree
    end

    # The engine (:native or :ruby) that produced the result (tree or
    # rejection) of the last Amath.parse call on the current thread that
    # reached the parser; nil before any parse. Under engine: :auto this is
    # :ruby when the native engine hit its recursion limit and amath reran
    # the input on the Ruby engine.
    def last_engine
      Thread.current[:amath_last_engine]
    end

    def native_available?
      Parsanol::Native.available?
    rescue LoadError, StandardError
      false
    end

    attr_reader :artifact_path

    # Point Amath at another artifact (mainly for tests). Clears the cache so
    # the next parse loads it.
    def artifact_path=(path)
      @lock.synchronize do
        @artifact_path = path.to_s
        @artifact = nil
      end
    end

    # The loaded Parsanol::PARG::Artifact, loaded and verified once.
    def artifact
      @lock.synchronize { @artifact ||= load_artifact(@artifact_path) }
    end

    private

    def normalize_input(input)
      raise ArgumentError, "input must be a String, got #{input.class}" unless input.is_a?(String)

      text = input.encoding == Encoding::UTF_8 ? input : input.encode(Encoding::UTF_8)
      raise ArgumentError, "input is not valid UTF-8" unless text.valid_encoding?

      text
    rescue EncodingError => e
      raise ArgumentError, "input cannot be converted to UTF-8: #{e.message}"
    end

    def resolve_engine(engine)
      case engine
      when :auto then native_available? ? :native : :ruby
      when :ruby then :ruby
      when :native
        return :native if native_available?

        raise EngineUnavailable,
              "engine: :native requested but the Parsanol native extension " \
              "is not available on this platform (#{RUBY_PLATFORM}, Ruby #{RUBY_VERSION})"
      else
        raise ArgumentError, "unknown engine #{engine.inspect} (use #{ENGINES.map(&:inspect).join(', ')})"
      end
    end

    # Runs +mode+ and returns [tree, engine that produced it]. Under :auto
    # (+fallback+), input nested too deeply for the native engine is rerun
    # on the Ruby engine: either native's own recursion limit, or the Ruby
    # stack running out inside the native call (threads other than the
    # main one have a 1 MiB machine stack by default).
    def run_engine(artifact, entry, text, mode, fallback:)
      if mode == :native && too_deep_for_native_thread?(text)
        Thread.current[:amath_last_engine] = :native
        raise native_too_deep(text, "nesting depth over #{THREAD_NATIVE_DEPTH} off the main thread") unless fallback

        return [run(artifact, entry, text, :ruby), :ruby]
      end

      [run(artifact, entry, text, mode), mode]
    rescue NativeRecursionLimit => e
      Thread.current[:amath_last_engine] = :native
      raise native_too_deep(text, e.message) unless fallback

      [run(artifact, entry, text, :ruby), :ruby]
    rescue NestingTooDeep
      raise unless fallback && mode == :native

      [run(artifact, entry, text, :ruby), :ruby]
    end

    # Off the main thread the machine stack is small (1 MiB by default) and
    # the native engine overflows it at about 40 levels of brackets. A Ruby
    # stack overflow inside the native call crashes the process instead of
    # raising, so deep input never reaches native there.
    def too_deep_for_native_thread?(text)
      return false if Thread.current.equal?(Thread.main)

      depth = 0
      max = 0
      text.each_char do |char|
        if OPENING.include?(char)
          depth += 1
          max = depth if depth > max
        elsif CLOSING.include?(char)
          depth -= 1 if depth.positive?
        end
      end
      max > THREAD_NATIVE_DEPTH
    end

    def native_too_deep(text, detail)
      NestingTooDeep.new(
        "AsciiMath input nests deeper than the native engine's recursion limit " \
        "(#{detail}); use engine: :ruby or engine: :auto",
        input: text, byte_offset: nil, char_offset: nil
      )
    end

    def run(artifact, entry, text, mode)
      # Parsanol's mode: :native silently runs Ruby when the extension is
      # missing; resolve_engine has already checked availability.
      if mode == :native
        NativeRecursionGuard.watch { artifact.parse(entry, text, mode: :native) }
      else
        artifact.parse(entry, text, mode: mode)
      end
    rescue Parsanol::ParseFailed => e
      Thread.current[:amath_last_engine] = mode
      raise parse_error(e, artifact, entry, text)
    rescue SystemStackError
      Thread.current[:amath_last_engine] = mode
      raise NestingTooDeep.new(
        "AsciiMath input nests too deeply for the #{mode} engine (Ruby stack exhausted)",
        input: text, byte_offset: nil, char_offset: nil
      )
    rescue Parsanol::PARG::Error, Parsanol::GrammarError, Parsanol::Native::UnsupportedGrammar => e
      raise ArtifactError, "artifact #{@artifact_path} cannot be used: #{e.class}: #{e.message}"
    end

    def parse_error(error, artifact, entry, text)
      byte = parslet_position(artifact, entry, text) || deepest_position(error.parse_failure_cause)
      char = byte && char_offset(text, byte)
      where = byte ? " at character #{char} (byte #{byte})" : ""
      ParseError.new("AsciiMath input rejected#{where}: #{error.message.lines.first&.strip}",
                     input: text, byte_offset: byte, char_offset: char)
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

      children.map { |c| deepest_leaf(c) }.compact.max
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

    def char_offset(text, byte)
      text.byteslice(0, byte).force_encoding(Encoding::UTF_8).scrub.length
    end

    def load_artifact(path)
      raise ArtifactError, "artifact not found: #{path}" unless File.file?(path)

      artifact = Parsanol::PARG::Artifact.load(path)
      missing = DECIMAL_ENTRIES.values - artifact.entries
      unless missing.empty?
        raise ArtifactError, "artifact #{path} lacks required entries: #{missing.join(', ')}"
      end

      artifact
    rescue JSON::ParserError => e
      raise ArtifactError, "artifact #{path} is not valid JSON: #{e.message.lines.first&.strip}"
    rescue Parsanol::PARG::Error, SystemCallError, KeyError, TypeError, NoMethodError => e
      raise ArtifactError, "artifact #{path} is invalid: #{e.class}: #{e.message}"
    end
  end
end
