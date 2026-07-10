# frozen_string_literal: true

require "json"
require "time"
require "fontisan"

module Essenfont
  module Release
    # CoverageManifest: emits coverage.json for the website.
    #
    # Reads per-plane TTFs, counts glyphs + codepoints per face,
    # computes overall coverage percentage against the ucode gem's
    # assigned-codepoint count.
    module CoverageManifest
      module_function

      # Build the manifest hash from per-plane TTFs in out_dir.
      # @return [Hash]
      def build(out_dir:)
        catalog = Essenfont::UcodeRef.catalog
        assigned_total = Essenfont::UcodeRef.assigned_count

        subfonts = []
        total_cps = 0

        catalog.all_planes.each do |plane|
          next unless plane.short_name && Release::PLANES.include?(plane.short_name.to_sym)

          file = "Essenfont-#{plane.short_name}.ttf"
          path = File.join(out_dir, file)
          next unless File.exist?(path)

          face = Fontisan::FontLoader.load(path)
          glyph_count = face.table("maxp")&.num_glyphs || 0
          cp_count = (face.table("cmap")&.unicode_mappings || {}).size
          total_cps += cp_count

          subfonts << {
            name: plane.short_name.to_s,
            plane: plane.number,
            display_name: plane.display_name,
            range: Release::PLANE_RANGES[plane.short_name.to_sym] ||
                   "U+#{plane.range.begin.to_s(16).upcase}..U+#{plane.range.end.to_s(16).upcase}",
            glyph_count: glyph_count,
            codepoint_count: cp_count,
            ttf_url: file,
            woff2_url: file.sub(/\.ttf$/, ".woff2"),
            woff_url: file.sub(/\.ttf$/, ".woff")
          }
        end

        otc_path = File.join(out_dir, "Essenfont-Regular.otc")
        coverage_pct = (total_cps.to_f / assigned_total * 100).round(2)

        {
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
      end

      # Build and write coverage.json to out_dir.
      # @return [Hash] the manifest that was written
      def emit(out_dir:)
        manifest = build(out_dir:)
        File.write(File.join(out_dir, "coverage.json"), JSON.pretty_generate(manifest))
        manifest
      end
    end
  end
end
