#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract per-codepoint SVG files from an SFNT font (TTF, OTF, TTC, or OTC).
#
# Standalone entry point — delegates to Essenfont::Release::SvgExports.
# Optional donor attribution via $DONOR_MAP (path to cp_map.json).

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "essenfont"

input = ARGV[0]
out_dir = ARGV[1] || "svg-exports"

# Auto-detect input font if not specified.
input ||= %w[Essenfont-Regular.otc Essenfont-Regular.ttc Essenfont-BMP.ttf].find { |p| File.exist?(p) }
raise ArgumentError, "no input font found — pass INPUT.ttf as the first argument" unless input

# Optional donor map for per-glyph attribution.
donor_map = {}
cp_map_path = ENV.fetch("DONOR_MAP", "cp_map.json")
if File.exist?(cp_map_path)
  data = JSON.parse(File.read(cp_map_path))
  donor_map = data.transform_values { |v| { label: (v["label"] || v[:label]).to_sym } }
                  .transform_keys { |k| k.to_i(16) rescue k.to_i }
  puts "→ loaded #{donor_map.size} cps from #{cp_map_path}"
end

Essenfont::Release::SvgExports.emit(out_dir: out_dir, font_path: input, donor_map: donor_map)
puts "✓ wrote SVGs to #{out_dir}/"
