#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit a coverage manifest for the website.
#
# Reads the latest built OTC + per-plane TTFs, computes per-subfont
# glyph/cp counts via Fontisan::Collection::Reader, and writes a JSON
# manifest the website consumes to drive its Download and Subfonts pages.
# Plane metadata + assigned-codepoint count come from the ucode gem.
#
# Usage:
#   ruby scripts/emit_coverage_manifest.rb > coverage.json

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "time"
require "fileutils"
require "fontisan"
require "ucode"
require "essenfont"

module EmitCoverage
  ROOT = File.expand_path("..", __dir__)

  # Map Unicode plane short names (from ucode) to the per-plane TTF filename.
  PLANE_FILES = {
    BMP: "Essenfont-BMP.ttf",
    SMP: "Essenfont-SMP.ttf",
    SIP: "Essenfont-SIP.ttf",
    TIP: "Essenfont-TIP.ttf",
    SSP: "Essenfont-SSP.ttf"
  }.freeze

  def self.emit
    catalog = Ucode::Unicode.for_version
    assigned_total = catalog.assigned_count

    subfonts = []
    total_cps = 0

    catalog.all_planes.each do |plane|
      next unless plane.short_name && PLANE_FILES.key?(plane.short_name)

      path = File.join(ROOT, PLANE_FILES.fetch(plane.short_name))
      next unless File.exist?(path)

      face = Fontisan::FontLoader.load(path)
      glyph_count = face.table("maxp")&.num_glyphs || 0
      cp_count = (face.table("cmap")&.unicode_mappings || {}).size
      total_cps += cp_count

      subfonts << {
        name: plane.short_name.to_s,
        plane: plane.number,
        display_name: plane.display_name,
        range: "U+#{plane.range.begin.to_s(16).upcase}..U+#{plane.range.end.to_s(16).upcase}",
        glyph_count: glyph_count,
        codepoint_count: cp_count,
        ttf_url: PLANE_FILES.fetch(plane.short_name),
        woff2_url: PLANE_FILES.fetch(plane.short_name).sub(/\.ttf$/, ".woff2"),
        woff_url: PLANE_FILES.fetch(plane.short_name).sub(/\.ttf$/, ".woff")
      }
    end

    otc_path = File.join(ROOT, "Essenfont-Regular.otc")
    coverage_pct = (total_cps.to_f / assigned_total * 100).round(2)

    manifest = {
      unicode_version: catalog.version,
      essenfont_version: Essenfont::Otc::Version::STRING,
      released_at: Time.now.utc.iso8601,
      otc_url: "Essenfont-Regular.otc",
      otc_size_bytes: File.exist?(otc_path) ? File.size(otc_path) : nil,
      total_codepoints: total_cps,
      total_assigned: assigned_total,
      coverage_percent: coverage_pct,
      subfonts: subfonts
    }

    puts JSON.pretty_generate(manifest)
  end
end

EmitCoverage.emit
