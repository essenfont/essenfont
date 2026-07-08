# frozen_string_literal: true

source "https://rubygems.org"

# Use local source if the path env var is set AND the directory exists
# (dev workflow). Otherwise use the published RubyGems version.
#
# Override locally via:
#   export FONTISAN_PATH=/path/to/fontisan
#   export UCODE_PATH=/path/to/ucode
#
# Version floor 0.4.23: the Layer#add raise-on-conflict contract
# (fontisan PR #108, released in 0.4.23) is required so CbdtPropagator
# placeholders no longer overwrite outline glyphs sharing the same
# "gid{N}" name. Earlier versions silently corrupted the cmap of any
# face pulling from both an outline donor and a CBDT donor with
# overlapping gid space — the root cause of the CJK Ext G loss in
# Essenfont-Regular.ttc face 7 (4,939 → 1,022 codepoints).
fontisan_path = ENV.fetch("FONTISAN_PATH", nil)
if fontisan_path && Dir.exist?(fontisan_path)
  gem "fontisan", path: fontisan_path
else
  gem "fontisan", "~> 0.4", ">= 0.4.23"
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
