#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit a coverage manifest for the website.
#
# Uses Essenfont::Manifest + Essenfont::UcodeRef for all metadata.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "time"
require "essenfont"

module EmitCoverage
  ROOT = File.expand_path("..", __dir__)

  PLANE_FILES = {
    BMP: "Essenfont-BMP.ttf",
    SMP: "Essenfont-SMP.ttf",
    SIP: "Essenfont-SIP.ttf",
    TIP: "Essenfont-TIP.ttf",
    SSP: "Essenfont-SSP.ttf"
  }.freeze

  module_function

  def emit
    catalog = Essenfont::UcodeRef.catalog
    assigned_total = Essenfont::UcodeRef.assigned_count

    subfonts = []
    total_cps = 0

    catalog.all_planes.each do |plane|
      next unless plane.short_name && PLANE_FILES.key?(plane.short_name.to_sym)

      path = File.join(ROOT, PLANE_FILES.fetch(plane.short_name.to_sym))
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
        ttf_url: PLANE_FILES.fetch(plane.short_name.to_sym),
        woff2_url: PLANE_FILES.fetch(plane.short_name.to_sym).sub(/\.ttf$/, ".woff2"),
        woff_url: PLANE_FILES.fetch(plane.short_name.to_sym).sub(/\.ttf$/, ".woff")
      }
    end

    otc_path = File.join(ROOT, "Essenfont-Regular.otc")
    coverage_pct = (total_cps.to_f / assigned_total * 100).round(2)

    manifest = {
      unicode_version: Essenfont::UcodeRef.unicode_version,
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

require "fontisan"

EmitCoverage.emit
