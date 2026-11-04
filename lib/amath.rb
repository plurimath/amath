# frozen_string_literal: true

require "parsanol"

# AsciiMath parser backed by a compiled Parsanol (PARG) grammar artifact.
#
# See docs/parser-contract.adoc for the full contract.
module Amath
  autoload :VERSION, "amath/version"
  autoload :Error, "amath/errors"
  autoload :ParseError, "amath/errors"
  autoload :NestingTooDeep, "amath/errors"
  autoload :ArtifactError, "amath/errors"
  autoload :EngineUnavailable, "amath/errors"
  autoload :Artifact, "amath/artifact"
  autoload :Configuration, "amath/configuration"
  autoload :Engine, "amath/engine"
  autoload :ErrorPosition, "amath/error_position"
  autoload :Parser, "amath/parser"
  autoload :Renester, "amath/renester"
  autoload :RawTree, "amath/raw_tree"
  autoload :Model, "amath/model"
  autoload :Symbols, "amath/symbols"
  autoload :Pma, "amath/pma"

  # Decimal marker => artifact entry name.
  DECIMAL_ENTRIES = Configuration::DECIMAL_ENTRIES
  ENGINES = Configuration::ENGINES
  DIALECTS = Configuration::DIALECTS
  THREAD_NATIVE_DEPTH = Configuration::THREAD_NATIVE_DEPTH
  OPENING = Configuration::OPENING
  CLOSING = Configuration::CLOSING
  DEFAULT_ARTIFACT_PATH = Configuration::DEFAULT_ARTIFACT_PATH

  @artifact = Artifact.new(DEFAULT_ARTIFACT_PATH)

  module_function

  # Parse +input+ and return its typed model (see docs/parser-contract.adoc).
  #
  # dialect: :legacy (the default) reads dialect L and returns an
  # Amath::Model::Document; empty input is a Document whose expression is
  # nil. dialect: :pma reads pma (plurimath docs/pma.adoc) with its own
  # artifact and returns an Amath::Model::PmaDocument; a refusal is an
  # Amath::ParseError with a #category. Any other dialect is an
  # ArgumentError, raised before an artifact is loaded.
  #
  # The engine that ran is available afterwards from Amath.last_engine.
  def parse(input, dialect: :legacy, decimal: ".", engine: :auto)
    case dialect
    when :legacy then Parser.parse(input, decimal: decimal, engine: engine)
    when :pma then Pma.parse(input, decimal: decimal, engine: engine)
    else
      raise ArgumentError,
            "unknown dialect #{dialect.inspect} (use #{DIALECTS.map(&:inspect).join(', ')})"
    end
  end

  # The engine (:native or :ruby) that produced the result (tree or
  # rejection) of the last Amath.parse call on the current thread that
  # reached the parser; nil before any parse. Under engine: :auto this is
  # :ruby when the native engine hit its recursion limit and amath reran
  # the input on the Ruby engine.
  def last_engine
    Engine.last_engine
  end

  def native_available?
    Engine.native_available?
  end

  def artifact_path
    @artifact.path
  end

  # Point Amath at another artifact (mainly for tests). Clears the cache so
  # the next parse loads it.
  def artifact_path=(path)
    @artifact.path = path
  end

  # The loaded Parsanol::PARG::Artifact, loaded and verified once.
  def artifact
    @artifact.fetch
  end

  # The artifact's declared Ruby bindings, paired with #artifact.
  def bindings
    @artifact.bindings
  end
end

# Installs a hook into Parsanol at load time, so it is required, not
# autoloaded.
require_relative "amath/native_recursion_guard"
