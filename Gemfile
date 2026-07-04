# frozen_string_literal: true

source "https://rubygems.org"

# Use local source if the path env var is set AND the directory exists
# (dev workflow). Otherwise fall back to the GitHub main branch — the
# published RubyGems 0.4.9 predates the remap:/unicode= fixes
# (commits 19f25b4, 78a78a0, 3ae9565), so we need HEAD until 0.4.10
# is released.
#
# Override locally via:
#   export FONTISAN_PATH=/path/to/fontisan
#   export UCODE_PATH=/path/to/ucode
fontisan_path = ENV["FONTISAN_PATH"]
if fontisan_path && Dir.exist?(fontisan_path)
  gem "fontisan", path: fontisan_path
else
  gem "fontisan", github: "fontist/fontisan", branch: "main"
end

ucode_path = ENV["UCODE_PATH"]
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
