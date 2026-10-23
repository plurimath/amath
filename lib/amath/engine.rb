# frozen_string_literal: true

module Amath
  # Runs a parse on the native or Ruby Parsanol engine: resolves the
  # requested engine, reruns input too deep for native on Ruby under
  # engine: :auto, maps Parsanol failures to Amath errors, and records the
  # engine that produced the result per thread.
  module Engine
    LAST_ENGINE_KEY = :amath_last_engine

    module_function

    # See Amath.last_engine.
    def last_engine
      Thread.current[LAST_ENGINE_KEY]
    end

    def native_available?
      Parsanol::Native.available?
    rescue LoadError, StandardError
      false
    end

    # The engine (:native or :ruby) that +engine+ (one of ENGINES) runs.
    def resolve(engine)
      case engine
      when :auto then native_available? ? :native : :ruby
      when :ruby then :ruby
      when :native
        return :native if native_available?

        raise EngineUnavailable,
              "engine: :native requested but the Parsanol native extension " \
              "is not available on this platform (#{RUBY_PLATFORM}, Ruby #{RUBY_VERSION})"
      else
        raise ArgumentError,
              "unknown engine #{engine.inspect} (use #{Configuration::ENGINES.map(&:inspect).join(', ')})"
      end
    end

    # Parses +text+ from +entry+ on +mode+ and returns the tree.
    def run(artifact, entry, text, mode, fallback:)
      tree, ran = run_with_fallback(artifact, entry, text, mode,
                                    fallback: fallback)
      record(ran)
      tree
    end

    # Runs +mode+ and returns [tree, engine that produced it]. Under :auto
    # (+fallback+), input nested too deeply for the native engine is rerun
    # on the Ruby engine: either native's own recursion limit, or the Ruby
    # stack running out inside the native call (threads other than the
    # main one have a 1 MiB machine stack by default).
    def run_with_fallback(artifact, entry, text, mode, fallback:)
      if mode == :native && too_deep_for_native_thread?(text)
        record(:native)
        unless fallback
          raise native_too_deep(
            text,
            "nesting depth over #{Configuration::THREAD_NATIVE_DEPTH} " \
            "off the main thread",
          )
        end

        return [run_mode(artifact, entry, text, :ruby), :ruby]
      end

      [run_mode(artifact, entry, text, mode), mode]
    rescue NativeRecursionLimit => e
      record(:native)
      raise native_too_deep(text, e.message) unless fallback

      [run_mode(artifact, entry, text, :ruby), :ruby]
    rescue NestingTooDeep
      raise unless fallback && mode == :native

      [run_mode(artifact, entry, text, :ruby), :ruby]
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
        if Configuration::OPENING.include?(char)
          depth += 1
          max = depth if depth > max
        elsif Configuration::CLOSING.include?(char)
          depth -= 1 if depth.positive?
        end
      end
      max > Configuration::THREAD_NATIVE_DEPTH
    end

    def native_too_deep(text, detail)
      NestingTooDeep.new(
        "AsciiMath input nests deeper than the native engine's recursion limit " \
        "(#{detail}); use engine: :ruby or engine: :auto",
        input: text, byte_offset: nil, char_offset: nil,
      )
    end

    def run_mode(artifact, entry, text, mode)
      # Parsanol's mode: :native silently runs Ruby when the extension is
      # missing; resolve has already checked availability.
      if mode == :native
        NativeRecursionGuard.watch do
          artifact.parse(entry, text, mode: :native)
        end
      else
        artifact.parse(entry, text, mode: mode)
      end
    rescue Parsanol::ParseFailed => e
      record(mode)
      raise parse_error(e, artifact, entry, text)
    rescue SystemStackError
      record(mode)
      raise NestingTooDeep.new(
        "AsciiMath input nests too deeply for the #{mode} engine (Ruby stack exhausted)",
        input: text, byte_offset: nil, char_offset: nil,
      )
    rescue Parsanol::PARG::Error, Parsanol::GrammarError,
           Parsanol::Native::UnsupportedGrammar => e
      raise ArtifactError,
            "artifact #{Amath.artifact_path} cannot be used: #{e.class}: #{e.message}"
    end

    def parse_error(error, artifact, entry, text)
      byte = ErrorPosition.byte_offset(error, artifact, entry, text)
      char = byte && ErrorPosition.char_offset(text, byte)
      where = byte ? " at character #{char} (byte #{byte})" : ""
      ParseError.new("AsciiMath input rejected#{where}: #{error.message.lines.first&.strip}",
                     input: text, byte_offset: byte, char_offset: char)
    end

    def record(mode)
      Thread.current[LAST_ENGINE_KEY] = mode
    end

    private_class_method :run_with_fallback, :native_too_deep, :run_mode,
                         :parse_error, :record, :too_deep_for_native_thread?
  end
end
