# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The artifact job in CI recompiles the grammar with the Parsanol version
# recorded in artifacts/asciimath.checksums.txt, so a newer Parsanol release
# cannot change the bytes it compares.
gem "parsanol", ENV.fetch("PARSANOL_VERSION") if ENV["PARSANOL_VERSION"]

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
# unitsdb unit symbols and names for scripts/check_reserved_words.rb.
gem "unitsdb", "~> 2.2"

group :development do
  gem "rubocop"
  gem "rubocop-performance"
  gem "rubocop-rake"
  gem "rubocop-rspec"
end
