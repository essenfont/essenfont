#!/usr/bin/env ruby
# frozen_string_literal: true

# Image-based code-chart glyph extractor.
# Renders a Unicode Code Chart PDF to PNG, then crops each grid cell
# to produce per-codepoint PNG glyphs. Used for blocks where ucode's
# vector SVG extractor returns 0 (e.g., Garay, Ol Onal).
#
# Usage: ruby extract-chart-png.rb <pdf_path> <first_cp_hex> <last_cp_hex> <output_dir>

require "fileutils"

pdf = ARGV[0]
first_cp = ARGV[1].to_i(16)
last_cp = ARGV[2].to_i(16)
out = ARGV[3]

FileUtils.mkdir_p(out)

# Render PDF page 2 (page 1 is boilerplate) to PNG at 300 DPI
tmp_ppm = "/tmp/chart-extract-#{Time.now.to_i}"
system("pdftoppm -f 2 -l 2 -r 300 -png #{pdf} #{tmp_ppm}")
png_file = Dir.glob("#{tmp_ppm}*.png").first
unless png_file
  # Try page 1 (some charts have grid on page 1)
  system("pdftoppm -f 1 -l 1 -r 300 -png #{pdf} #{tmp_ppm}")
  png_file = Dir.glob("#{tmp_ppm}*.png").first
end
abort "Failed to render PDF" unless png_file

puts "Rendered: #{png_file}"

# Get image dimensions
dims = `sips -g pixelWidth -g pixelHeight "#{png_file}"`.scan(/\d+/)
width = dims[0].to_i
height = dims[1].to_i
puts "Image: #{width}x#{height}"

# The Unicode code chart grid (on page 2) has this layout:
# - 16 columns (hex digits 0-F)
# - Variable rows (depends on block size)
# - Each cell shows: codepoint number + glyph + possibly character name
#
# The grid starts below the block title and range info.
# Approximate grid geometry (for US Letter at 300 DPI = 2550x3300):
# - Left margin: ~300px
# - Top of grid: ~500px
# - Column width: ~135px
# - Row height: ~135px (glyph area) + ~60px (label area)
#
# These need tuning per-chart. For now, use a simple approach:
# scan rows of 16 and crop each cell's center (where the glyph is).

# Grid parameters (empirically tuned for Unicode code charts at 300 DPI)
cols = 16
cell_w = (width - 600) / cols  # available width / 16
margin_left = 300
margin_top = 480
cell_h = 195  # total height per cell (glyph + label + spacing)

total_cps = last_cp - first_cp + 1
rows_needed = (total_cps / cols.to_f).ceil

puts "Grid: #{cols} cols x #{rows_needed} rows = #{cols * rows_needed} cells"
puts "Cell size: #{cell_w}x#{cell_h}"

count = 0
rows_needed.times do |row|
  16.times do |col|
    cp = first_cp + (row * 16) + col
    break if cp > last_cp

    # Crop the glyph area (top 2/3 of the cell, centered)
    x = margin_left + (col * cell_w) + 10
    y = margin_top + (row * cell_h)
    w = cell_w - 20
    h = cell_h * 2 / 3  # glyph area (above the codepoint label)

    cp_hex = "U+#{cp.to_s(16).upcase}"
    out_png = File.join(out, "#{cp_hex}.png")

    # Use sips to crop (macOS built-in)
    system("sips -c #{h} #{w} --cropOffset #{y} #{x} '#{png_file}' --out '#{out_png}' 2>/dev/null")

    if File.exist?(out_png) && File.size(out_png) > 100
      count += 1
    else
      # Cell may be empty (unassigned codepoint); skip
      FileUtils.rm_f(out_png)
    end
  end
end

puts "Extracted #{count} glyph PNGs to #{out}"

# Cleanup
FileUtils.rm_f(Dir.glob("#{tmp_ppm}*"))
