#!/usr/bin/env ruby
# frozen_string_literal: true

# merge-chart-glyphs.rb — Convert extracted code-chart SVGs to UFO
# glyphs and merge them into the committed per-plane UFOs.
#
# Input: directories of U+XXXX.svg files (produced by ucode code_chart extract)
# Output: .glif files appended to ufo/<plane>.ufo/glyphs/ + contents.plist updated
#
# Usage:
#   ruby scripts/merge-chart-glyphs.rb /tmp/code-chart-svgs/<Block>/<Block> [/more/paths...]

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "fontisan"

module MergeChartGlyphs
  UFO_DIR = File.expand_path("../ufo", __dir__)
  UPM = 1000

  PLANES = [
    { range: (0x0000..0xFFFF),  dir: "bmp.ufo" },
    { range: (0x10000..0x1FFFF), dir: "smp.ufo" },
    { range: (0x20000..0x2FFFF), dir: "sip.ufo" },
    { range: (0x30000..0x3FFFF), dir: "tip.ufo" },
    { range: (0xE0000..0xEFFFF), dir: "ssp.ufo" },
  ].freeze

  module_function

  def run(svg_dirs)
    puts "=== Merge code-chart glyphs into per-plane UFOs ==="
    svg_dirs.each { |dir| merge_dir(dir) }
  end

  def merge_dir(dir)
    svgs = Dir.glob(File.join(dir, "*.svg"))
    if svgs.empty?
      warn "  no SVGs in #{dir}, skipping"
      return
    end

    puts "  #{File.basename(dir)}: #{svgs.size} SVGs"

    # Group SVGs by target plane
    by_plane = Hash.new { |h, k| h[k] = [] }
    svgs.each do |svg|
      cp = codepoint_from_filename(File.basename(svg))
      next unless cp

      plane = plane_for_cp(cp)
      next unless plane

      by_plane[plane] << [cp, svg]
    end

    by_plane.each do |plane, items|
      merge_into_plane(plane, items)
    end
  end

  def merge_into_plane(plane, items)
    ufo_path = File.join(UFO_DIR, plane[:dir])
    glyphs_dir = File.join(ufo_path, "glyphs")
    contents_path = File.join(glyphs_dir, "contents.plist")

    abort "missing UFO: #{ufo_path}" unless File.directory?(ufo_path)

    # Read existing contents.plist
    contents = Fontisan::Ufo::Plist.parse(File.read(contents_path))

    added = 0
    skipped = 0
    items.each do |cp, svg|
      ufo_name = cp < 0x10000 ? "uni%04X" % cp : "u%05X" % cp
      glif_filename = "#{ufo_name}.glif"
      glif_path = File.join(glyphs_dir, glif_filename)

      if contents.key?(ufo_name)
        skipped += 1
        next
      end

      glyph = Fontisan::SvgToGlyf.from_svg_file(svg, upm: UPM, codepoint: cp)
      File.write(glif_path, glyph.to_glif)
      contents[ufo_name] = glif_filename
      added += 1
    end

    # Write updated contents.plist
    File.write(contents_path, Fontisan::Ufo::Plist.emit(contents))

    puts "    → #{plane[:dir]}: #{added} added, #{skipped} already present"
  end

  def codepoint_from_filename(basename)
    match = basename.match(/(?:U\+)?([0-9A-Fa-f]{4,6})\.svg\z/)
    return nil unless match

    match[1].to_i(16)
  end

  def plane_for_cp(cp)
    PLANES.find { |p| p[:range].cover?(cp) }
  end
end

if __FILE__ == $PROGRAM_NAME
  svg_dirs = ARGV.dup
  if svg_dirs.empty?
    abort "Usage: #{$PROGRAM_NAME} <svg_dir> [<svg_dir>...]"
  end

  MergeChartGlyphs.run(svg_dirs)
end
