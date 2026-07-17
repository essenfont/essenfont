#!/usr/bin/env ruby
# frozen_string_literal: true

# build-from-ufos.rb — Compile Essenfont directly from committed UFOs.
#
# This is the fast compile path of the UFO-first architecture:
#   Phase 1 (import-to-ufos.rb): donor fonts → per-plane UFOs
#   Phase 2 (THIS SCRIPT):       per-plane UFOs → output font
#
# Usage:
#   ruby scripts/build-from-ufos.rb                          # OTC (CFF2, canonical)
#   ruby scripts/build-from-ufos.rb --format=ttc             # TTC (glyf)
#   ruby scripts/build-from-ufos.rb --format=ttf-per-plane   # per-plane TTFs
#
# Expected build time: 5-10 minutes (down from 30-60 min with donor pipeline).
# No donor loading, no CpMap, no normalization — just reads UFOs and compiles.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "optparse"
require "fileutils"
require "essenfont"
require "fontisan"

module BuildFromUfos
  UFO_DIR = File.expand_path("../ufo", __dir__)
  OUTPUT_DIR = File.expand_path("..", __dir__)
  PLANES = [
    { name: :bmp, short: "BMP", num: 0 },
    { name: :smp, short: "SMP", num: 1 },
    { name: :sip, short: "SIP", num: 2 },
    { name: :tip, short: "TIP", num: 3 },
    { name: :ssp, short: "SSP", num: 14 },
  ].freeze

  module_function

  def run(format:)
    puts "=== Build from UFOs (format: #{format}) ==="

    ufos = load_plane_ufos
    return if ufos.empty?

    total_glyphs = ufos.sum { |_, u| u.glyphs.size }
    puts "  loaded #{ufos.size} plane UFOs, #{total_glyphs} total glyphs"
    puts ""

    case format.to_sym
    when :otc, :otc_cff2
      build_collection(ufos, subfont_format: :otf2, ext: ".otc")
    when :ttc
      build_collection(ufos, subfont_format: :ttf, ext: ".ttc")
    when :'ttf-per-plane'
      build_per_plane(ufos)
    else
      abort "unknown format: #{format} (use otc, ttc, or ttf-per-plane)"
    end
  end

  def load_plane_ufos
    ufos = {}
    PLANES.each do |plane|
      path = File.join(UFO_DIR, "#{plane[:name]}.ufo")
      unless File.directory?(path)
        warn "  WARNING: #{path} not found — run scripts/import-to-ufos.rb first"
        next
      end

      ufo = Fontisan::Ufo::Font.new
      ufo.path = path
      Fontisan::Ufo::Reader.new(ufo).read
      puts "  #{plane[:short]}: #{ufo.glyphs.size} glyphs"
      ufos[plane[:name]] = ufo
    end
    ufos
  end

  def build_collection(ufos, subfont_format:, ext:)
    suffix = subfont_format == :otf2 ? "-CFF2" : ""
    output_path = File.join(OUTPUT_DIR, "Essenfont#{suffix}-Regular#{ext}")

    puts "→ Building collection (#{subfont_format})"

    stitcher = Fontisan::Stitcher.new
    subfont_names = []

    PLANES.each do |plane|
      ufo = ufos[plane[:name]]
      next unless ufo

      source_label = plane[:name]
      subfont_name = "plane_#{plane[:num]}"
      subfont_names << subfont_name

      stitcher.add_source(source_label, ufo)

      # Include all unicode-mapped glyphs from this source
      cp_map = {}
      ufo.glyphs.each_value do |glyph|
        glyph.unicodes.each { |cp| cp_map[cp] = source_label }
      end

      stitcher.include_codepoints_map(cp_map, into: subfont_name)
      puts "  #{plane[:short]}: #{cp_map.size} codepoints → #{subfont_name}"
    end

    stitcher.set_info(
      family_name: Essenfont::Otc::Naming::FAMILY,
      style_name: Essenfont::Otc::Naming::SUBFAMILY,
      version_major: Essenfont::Otc::Naming.version_major,
      version_minor: Essenfont::Otc::Naming.version_minor,
      copyright: Essenfont::Otc::Naming::COPYRIGHT
    )

    collection = stitcher.write_collection(output_path, format: subfont_format)
    puts "=== Wrote #{output_path} (#{collection.bytes} bytes, #{collection.face_count} faces) ==="

    # MetricsPass + validation
    Essenfont::Otc::MetricsPass.recompute!(collection.path)
    failures = Essenfont::Otc::Validator.check(
      collection.path,
      expected_faces: collection.face_count
    )
    if failures.empty?
      puts "  validated: #{collection.face_count} faces"
    else
      failures.each { |f| warn "  FAIL: #{f.message}" }
    end
  end

  def build_per_plane(ufos)
    puts "→ Building per-plane TTFs"

    PLANES.each do |plane|
      ufo = ufos[plane[:name]]
      next unless ufo

      output_path = File.join(OUTPUT_DIR, "Essenfont-#{plane[:short]}.ttf")
      stitcher = Fontisan::Stitcher.new
      stitcher.add_source(plane[:name], ufo)

      cp_map = {}
      ufo.glyphs.each_value do |glyph|
        glyph.unicodes.each { |cp| cp_map[cp] = plane[:name] }
      end
      stitcher.include_codepoints_map(cp_map, into: :main)

      stitcher.write_to(output_path, format: :ttf, subfont: :main)
      puts "  #{plane[:short]}: #{File.size(output_path)} bytes"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  format = :otc
  OptionParser.new do |opts|
    opts.banner = "Usage: build-from-ufos.rb [options]"
    opts.on("--format=FORMAT", "otc (default), ttc, ttf-per-plane") do |v|
      format = v.tr("-", "_").to_sym
    end
  end.parse!

  BuildFromUfos.run(format: format)
end
