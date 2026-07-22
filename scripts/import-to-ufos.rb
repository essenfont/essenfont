#!/usr/bin/env ruby
# frozen_string_literal: true

# import-to-ufos.rb — Import donor fonts into committed per-plane UFOs.
#
# This is the first phase of the UFO-first build architecture:
#   Phase 1 (this script): donor fonts → per-plane UFOs (committed to repo)
#   Phase 2 (build.rb):    per-plane UFOs → output font (fast compile)
#
# Usage:
#   ruby scripts/import-to-ufos.rb                  # gaps-only (default)
#   ruby scripts/import-to-ufos.rb --full           # full rebuild
#   ruby scripts/import-to-ufos.rb --stats          # print coverage only
#
# The UFOs are written to ufo/{plane}.ufo/ and should be committed to git.
# Manual glyph edits in the UFOs survive re-imports in gaps-only mode.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "optparse"
require "fileutils"
require "essenfont"
require "fontisan"

module ImportToUfos
  UFO_DIR = File.expand_path("../ufo", __dir__)
  PLANES = {
    bmp: (0x0000..0xFFFF),
    smp: (0x10000..0x1FFFF),
    sip: (0x20000..0x2FFFF),
    tip: (0x30000..0x3FFFF),
    ssp: (0xE0000..0xEFFFF),
  }.freeze

  module_function

  def run(mode:)
    puts "=== Import donors to UFOs (mode: #{mode}) ==="

    manifest = Essenfont::Manifest.load
    puts "  manifest: #{manifest.size} entries (#{manifest.active.size} active)"

    donors = Essenfont::DonorLoader.new(manifest: manifest).load_all
    raise "no donors loaded" if donors.empty?

    puts "  loaded #{donors.size} donors"

    # Build the CpMap to know which codepoint comes from which donor
    cp_map = Essenfont::CpMap.build_from(donors)
    puts "  cp_map: #{cp_map.size} codepoints"
    puts ""

    # Load existing UFOs (for gaps-only mode)
    existing = mode == :full ? {} : load_existing_ufos

    # Distribute glyphs from donors to per-plane UFOs
    plane_fonts = create_plane_fonts

    added = Hash.new(0)
    skipped = Hash.new(0)

    donors.each_value do |donor|
      donor.ufo&.glyphs&.each do |_name, glyph|
        cp = glyph.unicodes.first
        next unless cp

        plane = plane_for_codepoint(cp)
        next unless plane

        # Use Unicode-conventional glyph name (avoids cross-donor name clashes)
        ufo_name = cp < 0x10000 ? "uni%04X" % cp : "u%05X" % cp

        # In gaps-only mode, skip if the glyph already exists
        if existing[plane]&.include?(ufo_name)
          skipped[plane] += 1
          next
        end

        # Check if this donor is the assigned one for this codepoint
        assigned = cp_map[cp]
        next unless assigned && assigned[:label] == donor.label

        # Create a new glyph with the conventional name, preserving data
        ufo_glyph = Fontisan::Ufo::Glyph.new(name: ufo_name)
        ufo_glyph.width = glyph.width
        ufo_glyph.height = glyph.height if glyph.height
        glyph.unicodes.each { |uc| ufo_glyph.add_unicode(uc) }
        glyph.contours.each { |c| ufo_glyph.add_contour(c) }

        plane_fonts[plane].layers.default_layer.add(ufo_glyph)
        added[plane] += 1
      end
    end

    # Ensure .notdef exists in each plane
    plane_fonts.each do |plane, ufo|
      next if ufo.glyphs.key?(".notdef")
      notdef = Fontisan::Ufo::Glyph.new(name: ".notdef")
      notdef.width = 1000
      ufo.layers.default_layer.add(notdef)
    end

    # Set font info for each plane
    plane_fonts.each do |plane, ufo|
      info = ufo.info
      info.units_per_em = 1000
      info.family_name = "Essenfont #{plane.to_s.upcase}"
      info.style_name = "Regular"
      info.version_major = 0
      info.version_minor = 5
      info.copyright = "OFL 1.1 + FSung-NC (CJK glyphs)"
      info.postscript_font_name = "Essenfont-#{plane.to_s.upcase}"
    end

    # Write UFOs
    puts "=== Writing per-plane UFOs ==="
    total = 0
    plane_fonts.each do |plane, ufo|
      path = File.join(UFO_DIR, "#{plane}.ufo")
      glyph_count = ufo.glyphs.size

      if mode == :stats
        puts "  #{plane}: #{glyph_count} glyphs (stats only)"
        total += glyph_count
        next
      end

      FileUtils.rm_rf(path) if mode == :full
      Fontisan::Ufo::Writer.new(ufo).write(path)
      new_count = added[plane]
      skip_count = skipped[plane]
      puts "  #{plane}: #{glyph_count} glyphs (#{new_count} new, #{skip_count} existing)"
      total += glyph_count
    end

    puts ""
    puts "Total: #{total} glyphs across #{plane_fonts.size} planes"

    # Coverage report
    puts ""
    print_coverage(donors, cp_map)
  end

  def create_plane_fonts
    PLANES.each_with_object({}) do |(plane, _), h|
      h[plane] = Fontisan::Ufo::Font.new
    end
  end

  def plane_for_codepoint(cp)
    PLANES.each do |plane, range|
      return plane if range.cover?(cp)
    end
    nil
  end

  def load_existing_ufos
    existing = {}
    PLANES.each_key do |plane|
      path = File.join(UFO_DIR, "#{plane}.ufo")
      next unless File.directory?(path)

      begin
        ufo = Fontisan::Ufo::Font.new
        ufo.path = path
        Fontisan::Ufo::Reader.new(ufo).read
        existing[plane] = ufo.glyphs.keys.to_set
        puts "  loaded existing #{plane}.ufo: #{existing[plane].size} glyphs"
      rescue StandardError => e
        warn "  warning: could not read #{path}: #{e.message}"
      end
    end
    existing
  end

  def print_coverage(donors, cp_map)
    catalog = Essenfont::UcodeRef.catalog
    assigned = Essenfont::UcodeRef.assigned_count
    assigned_set = Essenfont::UcodeRef.assigned_codepoints

    puts "=== Coverage ==="
    puts "  assigned codepoints: #{assigned}"
    puts "  covered by donors:   #{cp_map.size}"
    puts "  coverage:            #{(cp_map.size.to_f / assigned * 100).round(2)}%"

    uncovered = []
    catalog.all_blocks.each do |block|
      block_cps = (block.first_cp..block.last_cp).to_a
      assigned_in_block = block_cps.select { |cp| assigned_set.include?(cp) }
      next if assigned_in_block.empty?

      missing = assigned_in_block.reject { |cp| cp_map.donor_labels.key?(cp) }
      next if missing.empty?

      covered_count = assigned_in_block.size - missing.size
      pct = (covered_count.to_f / assigned_in_block.size * 100).round(1)
      uncovered << "#{block.id}: #{covered_count}/#{assigned_in_block.size} (#{pct}%)"
    end

    if uncovered.any?
      puts ""
      puts "  Partially/uncovered blocks:"
      uncovered.first(20).each { |line| puts "    #{line}" }
      puts "    ... and #{[0, uncovered.size - 20].max} more" if uncovered.size > 20
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  mode = :gaps
  OptionParser.new do |opts|
    opts.banner = "Usage: import-to-ufos.rb [options]"
    opts.on("--full", "Full rebuild (overwrites existing UFOs)") { mode = :full }
    opts.on("--stats", "Print coverage only, don't write") { mode = :stats }
  end.parse!

  ImportToUfos.run(mode: mode)
end
