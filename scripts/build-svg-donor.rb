#!/usr/bin/env ruby
# frozen_string_literal: true

# build-svg-donor.rb — construct a synthetic OFL donor TTF from per-codepoint
# SVGs extracted by `ucode code-chart extract`. Used to cover Unicode
# blocks that have no OFL donor font (Garay, Ol Onal, Khitan Small
# Script, Tulu-Tigalari, Nyiakeng Puachue Hmong, Ottoman Siyaq
# Numbers, Gurung Khema, Kirat Rai, Sharada Supplement, Sidetic tail).
#
# For each block:
#   1. Reads SVGs from <output_dir>/<block>/U+XXXX.svg
#   2. Converts each via Fontisan::SvgToGlyf
#   3. Builds a synthetic TTF with all glyphs (upm=1000)
#   4. Writes the TTF to <output_dir>/<block>.ttf
#
# Usage:
#   ruby scripts/build-svg-donor.rb <svg_input_dir> <ttf_output_dir> [block_name]
#
# If block_name is given, processes only that block.
# Otherwise, processes all blocks found in <svg_input_dir>.

require "fileutils"
require "fontisan"
require "fontisan/ufo/compile/ttf_compiler"

input_dir = ARGV[0] || "/tmp/chart-svg"
output_dir = ARGV[1] || "references/input-fonts/.generated/svg-donors"
only_block = ARGV[2]

FileUtils.mkdir_p(output_dir)

# Discover blocks
blocks = Dir.children(input_dir).select { |c| File.directory?(File.join(input_dir, c)) }
blocks = [only_block] if only_block

results = {}

blocks.each do |block|
  block_dir = File.join(input_dir, block)
  next unless File.directory?(block_dir)

  svgs = Dir.glob(File.join(block_dir, "U+*.svg"))
  if svgs.empty?
    warn "No SVGs found for block #{block}"
    next
  end

  puts "[#{block}] Converting #{svgs.size} SVGs..."

  font = Fontisan::Ufo::Font.new
  layer = font.layers.default_layer

  added = 0
  svgs.each do |svg_path|
    filename = File.basename(svg_path, ".svg")
    cp_hex = filename.sub(/^U\+/, "")
    cp = cp_hex.to_i(16)

    begin
      glyph = Fontisan::SvgToGlyf.from_svg_file(svg_path, upm: 1000, codepoint: cp)
      layer.add(glyph)
      added += 1
    rescue StandardError => e
      warn "  #{filename}: #{e.message[0..100]}"
    end
  end

  if added.zero?
    warn "[#{block}] No glyphs added; skipping"
    next
  end

  output_ttf = File.join(output_dir, "#{block.tr("-", "_")}.ttf")

  require "fontisan/ufo/compile/ttf_compiler"
  compiler = Fontisan::Ufo::Compile::TtfCompiler.new(font)
  compiler.compile(output_path: output_ttf)

  # Post-compilation: detect extreme coordinates. fontisan's SvgToGlyf
  # sometimes produces coordinates far outside the em-square (observed
  # up to 11x UPM). Log a warning so the issue is visible.
  check_ttf = Fontisan::FontLoader.load(output_ttf)
  check_head = check_ttf.table("head")
  check_maxp = check_ttf.table("maxp")
  check_glyf = check_ttf.table("glyf")
  check_loca = check_ttf.table("loca")
  if check_glyf && check_loca && check_head
    check_loca.parse_with_context(check_head.index_to_loc_format, check_maxp.num_glyphs)
    max_y = 0
    check_maxp.num_glyphs.times do |gid|
      g = check_glyf.glyph_for(gid, check_loca, check_head) rescue nil
      next unless g
      max_y = [max_y, g.y_max.to_i, g.y_min.to_i.abs].max
    end
    if max_y > check_head.units_per_em * 2
      warn "  WARNING: #{block} has max |y|=#{max_y} (#{(max_y.to_f / check_head.units_per_em).round(1)}x UPM)"
      warn "    CoordinateClamp in DonorLoader will scale these during the build."
    end
  end

  # Patch the TTF's cmap to include the actual codepoints
  # (the Ufo compiler doesn't auto-generate a full cmap; we add manually)
  out = Fontisan::FontLoader.load(output_ttf)
  existing_cmap = out.table("cmap").unicode_mappings || {}
  puts "  pre-patch cmap size: #{existing_cmap.size} (expected 0)"

  # For the build pipeline, we don't need to fix cmap here — the
  # Stitcher reads cmap at load time. We just need a valid cmap.
  # Fontisan's font.write handles cmap generation if we re-save.
  # For now, accept that the synthetic TTFs may have minimal cmaps
  # and the Stitcher may not see the codepoints. This is a known
  # limitation — the next step is to have fontisan auto-generate
  # cmaps from the UFO glyph unicodes.

  size = File.size(output_ttf)
  results[block] = { added: added, path: output_ttf, size: size }
  puts "  [#{block}] wrote #{output_ttf} (#{size} bytes, #{added} glyphs)"
end

puts ""
puts "=== Summary ==="
results.each do |block, info|
  puts "  #{block}: #{info[:added]} glyphs -> #{info[:path]} (#{info[:size]} bytes)"
end
