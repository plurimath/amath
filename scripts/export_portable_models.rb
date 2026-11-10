# frozen_string_literal: true

# Consumes lutaml-model's portable bundle API; does not implement a codec.
# Pin the candidate/released framework in the calling environment.
require "json"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "lutaml/model"
require "lutaml/model/lml"
require "amath/model"

abort "portable LML bundle API is unavailable in this lutaml-model" unless Lutaml::Model::Lml.respond_to?(:export_bundle)
abort "usage: ruby scripts/export_portable_models.rb OUTPUT" unless ARGV.length == 1

# Ruby supplies implicit JSON attribute mappings. Declare that same mapping
# vocabulary in this isolated export process so foreign generators can see it;
# ordinary Ruby consumers keep their existing writer configuration.
Amath::Model.classes.each do |klass|
  names = klass.attributes.keys
  klass.json do
    names.each { |name| map name.to_s, to: name }
  end
end
bundle = Lutaml::Model::Lml.export_bundle([Amath::Model::Document, Amath::Model::PmaDocument])
File.write(ARGV.first, "#{JSON.pretty_generate(bundle.to_h)}\n")
puts "exported #{bundle.to_h.fetch('models').size} models to #{ARGV.first}"
