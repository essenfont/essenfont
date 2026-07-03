# frozen_string_literal: true

source "https://rubygems.org"

# ucode gemspec pins fontisan to = 0.2.22 (stale; ucode 0.3.x actually works
# with fontisan 0.4.x). Set FONTISAN_PATH so ucode's Gemfile picks up our
# local fontisan 0.4.8 instead of the published 0.2.22.
ENV["FONTISAN_PATH"] ||= "/Users/mulgogi/src/fontist/fontisan"

gem "fontisan", "~> 0.4", path: ENV["FONTISAN_PATH"]
gem "ucode", "~> 0.3", path: "/Users/mulgogi/src/fontist/ucode"
gem "rake"

group :development do
  gem "rspec"
  gem "rubocop"
end
gem "rubyzip", "~> 2.3", group: :development
gem "nokogiri", "~> 1.16", group: :development
