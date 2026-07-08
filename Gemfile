# frozen_string_literal: true

source "https://rubygems.org"

# Use local source if the path env var is set AND the directory exists
# (dev workflow). Otherwise use the published RubyGems version.
#
# Override locally via:
#   export FONTISAN_PATH=/path/to/fontisan
#   export UCODE_PATH=/path/to/ucode
fontisan_path = ENV.fetch("FONTISAN_PATH", nil)
if fontisan_path && Dir.exist?(fontisan_path)
  gem "fontisan", path: fontisan_path
else
  gem "fontisan", "~> 0.4", ">= 0.4.10"
end

ucode_path = ENV.fetch("UCODE_PATH", nil)
if ucode_path && Dir.exist?(ucode_path)
  gem "ucode", path: ucode_path
else
  gem "ucode", "~> 0.3", ">= 0.3.3"
end

gem "rake"

group :development do
  gem "nokogiri", "~> 1.16"
  gem "rspec"
  gem "rubocop"
  gem "rubyzip", "~> 2.3"
end
