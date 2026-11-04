# frozen_string_literal: true

require "json"

module Amath
  # The compiled grammar artifact Amath parses with: loaded and verified
  # once per path, and reloaded after the path changes.
  class Artifact
    # Loads the Parsanol::PARG::Artifact at +path+ and checks it has an
    # entry for every decimal marker. Every load failure is an ArtifactError.
    def self.load(path)
      raise ArtifactError, "artifact not found: #{path}" unless File.file?(path)

      artifact = Parsanol::PARG::Artifact.load(path)
      missing = Configuration::DECIMAL_ENTRIES.values - artifact.entries
      unless missing.empty?
        raise ArtifactError,
              "artifact #{path} lacks required entries: #{missing.join(', ')}"
      end

      artifact
    rescue JSON::ParserError => e
      raise ArtifactError,
            "artifact #{path} is not valid JSON: #{e.message.lines.first&.strip}"
    rescue Parsanol::PARG::Error, SystemCallError, KeyError, TypeError,
           NoMethodError => e
      raise ArtifactError,
            "artifact #{path} is invalid: #{e.class}: #{e.message}"
    end

    attr_reader :path

    def initialize(path)
      @path = path
      @loaded = nil
      @bindings = nil
      @lock = Mutex.new
    end

    # Clears the loaded artifact so the next #fetch loads +path+.
    def path=(path)
      @lock.synchronize do
        @path = path.to_s
        @loaded = nil
        @bindings = nil
      end
    end

    # The Parsanol::PARG::Artifact at #path, loaded on first use.
    def fetch
      @lock.synchronize { @loaded ||= self.class.load(@path) }
    end

    # The declared Ruby binding artifact beside #path, verified and paired
    # with the parse artifact, loaded on first use.
    def bindings
      parse = fetch
      @lock.synchronize { @bindings ||= self.class.load_bindings(@path, parse) }
    end

    def self.bindings_path(path)
      path.to_s.sub(/\.json\z/, ".bindings.ruby.json")
    end

    def self.load_bindings(path, parse)
      file = bindings_path(path)
      raise ArtifactError, "binding artifact not found: #{file}" unless File.file?(file)

      Parsanol::PARG::Bindings::Artifact.from_json(File.read(file), target: "ruby")
                                        .pair_with!(parse)
    rescue Parsanol::PARG::Error, JSON::ParserError, SystemCallError => e
      raise ArtifactError, "binding artifact #{file} is invalid: #{e.class}: #{e.message}"
    end
  end
end
