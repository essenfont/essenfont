# frozen_string_literal: true

require "json"
require "zlib"
require "time"

module Essenfont
  module Release
    # Provenance: per-codepoint + per-block donor attribution.
    #
    # Maps every codepoint to its donor and every Unicode block to its
    # contributing donors. Emits provenance.json + .gz.
    module Provenance
      module_function

      # Build and write provenance.json + .gz to out_dir.
      # @param cp_map [Essenfont::CpMap] the build's codepoint→donor map
      def emit(out_dir:, cp_map:)
        manifest = Essenfont::Manifest.load
        catalog = Essenfont::UcodeRef.catalog

        donors_meta = build_donor_metadata(manifest)
        blocks_meta = compute_block_donors(catalog, cp_map)

        data = {
          essenfont_version: Essenfont::Otc::Version::STRING,
          ucd_version: Essenfont::UcodeRef.unicode_version,
          generated_at: Time.now.utc.iso8601,
          donor_count: donors_meta.size,
          codepoint_count: cp_map.size,
          donors: donors_meta,
          blocks: blocks_meta,
          codepoints: cp_map.donor_labels.transform_values { |label| { donor: label } }
        }

        json = JSON.generate(data)
        File.write(File.join(out_dir, "provenance.json"), json)
        Zlib::GzipWriter.open(File.join(out_dir, "provenance.json.gz")) { |gz| gz.write(json) }
        puts "  provenance: #{cp_map.size} cps, #{blocks_meta.size} blocks"
      end

      def build_donor_metadata(manifest)
        manifest.to_h do |entry|
          [entry.label, {
            family: entry.family,
            license: entry.license,
            version: entry.raw["version"],
            url: entry.url,
            sha256: entry.sha256
          }]
        end
      end

      def compute_block_donors(catalog, cp_map)
        labels = cp_map.donor_labels

        catalog.all_blocks.each_with_object({}) do |b, h|
          cps_in_block = labels.keys.grep(b.first_cp..b.last_cp)

          donor_counts = cps_in_block.each_with_object(Hash.new(0)) do |cp, counts|
            counts[labels[cp]] += 1
          end

          primary = donor_counts.max_by { |_, c| c }&.first

          h[b.id] = {
            first_cp: sprintf("0x%X", b.first_cp),
            last_cp: sprintf("0x%X", b.last_cp),
            primary_donor: primary,
            donors: donor_counts.keys,
            donor_counts: donor_counts.transform_keys(&:to_s),
            codepoint_count: cps_in_block.size
          }
        end
      end
    end
  end
end
