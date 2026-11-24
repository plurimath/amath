# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Exact artifact paired with the PMA checksum; replace after asciiunits 0.1.8 is released.
gem "asciiunits", git: "https://github.com/unitsml/asciiunits.git",
                  ref: "877382b92a52e0ac59869af371e1f41cd55a0437"

# The artifact job in CI recompiles the grammar with the Parsanol version
# recorded in artifacts/asciimath.checksums.txt, so a newer Parsanol release
# cannot change the bytes it compares.
gem "parsanol", ENV.fetch("PARSANOL_VERSION") if ENV["PARSANOL_VERSION"]

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
# unitsdb unit symbols and names for scripts/check_reserved_words.rb.
# Pinned: data/quantities.json (scripts/quantities.rb) is generated from it.
gem "unitsdb", "2.2.13"

group :development do
  gem "rubocop"
  gem "rubocop-performance"
  gem "rubocop-rake"
  gem "rubocop-rspec"
end
