# frozen_string_literal: true

require_relative "lib/amath/version"

Gem::Specification.new do |spec|
  spec.name = "amath"
  spec.version = Amath::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "AsciiMath parser by Plurimath."
  spec.description = <<~DESCRIPTION
    AsciiMath parser that runs a compiled Parsanol grammar artifact and
    returns a parse tree. Used by Plurimath.
  DESCRIPTION

  spec.homepage = "https://github.com/plurimath/amath"
  spec.license = "BSD-2-Clause"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*.rb", "artifacts/**/*", "corpora/**/*.yml",
        "docs/**/*", "README.adoc", "LICENSE.md"]
      .select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "parsanol", "~> 1.3", ">= 1.3.107"

  spec.metadata["rubygems_mfa_required"] = "true"
end
