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

  DEFAULT_ARTIFACT_PATH = File.expand_path("../artifacts/asciimath.json", __dir__)

  @artifact_path = DEFAULT_ARTIFACT_PATH
  @artifact = nil
  @lock = Mutex.new

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
      tree = run(artifact, entry, text, mode)
      Thread.current[:amath_last_engine] = mode
      tree
    end

    # The engine (:native or :ruby) that ran the last successful or rejected
    # Amath.parse call on the current thread; nil before any parse.
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

    def run(artifact, entry, text, mode)
      # Parsanol's mode: :native silently runs Ruby when the extension is
      # missing; resolve_engine has already checked availability.
      artifact.parse(entry, text, mode: mode)
    rescue Parsanol::ParseFailed => e
      Thread.current[:amath_last_engine] = mode
      raise parse_error(e, text)
    rescue Parsanol::PARG::Error, Parsanol::GrammarError, Parsanol::Native::UnsupportedGrammar => e
      raise ArtifactError, "artifact #{@artifact_path} cannot be used: #{e.class}: #{e.message}"
    end

    def parse_error(error, text)
      byte = deepest_position(error.parse_failure_cause)
      char = byte && char_offset(text, byte)
      where = byte ? " at character #{char} (byte #{byte})" : ""
      ParseError.new("AsciiMath input rejected#{where}: #{error.message.lines.first&.strip}",
                     input: text, byte_offset: byte, char_offset: char)
    end

    def deepest_position(cause)
      return nil unless cause

      ([cause.position] + cause.children.compact.map { |c| deepest_position(c) })
        .compact.max
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
