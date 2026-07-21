# frozen_string_literal: true

source "https://rubygems.org"

# Use local source if the path env var is set AND the directory exists
# (dev workflow). Otherwise use the published RubyGems version.
#
# Override locally via:
#   export FONTISAN_PATH=/path/to/fontisan
#   export UCODE_PATH=/path/to/ucode
#
# Version floor 0.4.43: SvgToGlyf viewBox parsing preserves min_x/min_y
# (fontisan 0.4.43) so SVG code-chart glyphs normalize correctly.
# 0.4.41: compound glyph decomposition in FromBinData (PR #129) and
# CFF charstring extraction (no longer a stub).
# Earlier versions silently dropped compound glyphs and stubbed CFF
# extraction, producing empty/phantom outlines for affected donors.
fontisan_path = ENV.fetch("FONTISAN_PATH", nil)
if fontisan_path && Dir.exist?(fontisan_path)
  gem "fontisan", path: fontisan_path
else
  gem "fontisan", "~> 0.4", ">= 0.4.43"
end

# Version floor 0.5.0: code_chart extract now handles CID-keyed fonts
# via the new positional-correlation tier, so Syriac Supplement (and
# other CID-keyed PDF fonts) extract correctly. Earlier versions
# silently returned 0 SVGs for CID-keyed PDFs without /ToUnicode.
ucode_path = ENV.fetch("UCODE_PATH", nil)
if ucode_path && Dir.exist?(ucode_path)
  gem "ucode", path: ucode_path
else
  gem "ucode", "~> 0.5", ">= 0.5.0"
end

gem "rake"

group :development do
  gem "nokogiri", "~> 1.16"
  gem "rspec"
  gem "rubocop"
  gem "rubyzip", "~> 2.3"
end
