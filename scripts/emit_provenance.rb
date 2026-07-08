#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit per-codepoint + per-block donor provenance for the website.
#
# Uses Essenfont::Manifest + Essenfont::UcodeRef for all metadata.
# No hardcoded paths; no inline YAML parsing.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "zlib"
require "essenfont"

module EmitProvenance
  ROOT = File.expand_path("..", __dir__)

  module_function

  def emit(out_dir: ".")
    cp_map = load_cp_map
    manifest = Essenfont::Manifest.load
    catalog = Essenfont::UcodeRef.catalog

    donors_meta = build_donor_metadata(manifest)
    blocks_meta = compute_block_donors(catalog, cp_map)

    manifest_data = {
      essenfont_version: Essenfont::Otc::Version::STRING,
      ucd_version: Essenfont::UcodeRef.unicode_version,
      generated_at: Time.now.utc.iso8601,
      donor_count: donors_meta.size,
      codepoint_count: cp_map.size,
      donors: donors_meta,
      blocks: blocks_meta,
      codepoints: cp_map.transform_values { |v| { donor: v[:label] } }
    }

    json = JSON.generate(manifest_data)
    out_path = File.join(out_dir, "provenance.json")
    File.write(out_path, json)
    Zlib::GzipWriter.open(File.join(out_dir, "provenance.json.gz")) { |gz| gz.write(json) }

    puts "wrote #{out_path} (#{(json.bytesize / 1024.0 / 1024).round(1)} MB)"
    puts "wrote #{out_path}.gz (#{(File.size("#{out_path}.gz") / 1024.0 / 1024).round(1)} MB)"
    puts "  #{donors_meta.size} donors, #{blocks_meta.size} blocks, #{cp_map.size} cps"
  end

  def self.load_cp_map
    path = File.join(ROOT, "cp_map.json")
    unless File.exist?(path)
      raise Essenfont::Otc::Errors::ManifestMissing,
            "cp_map.json not found at #{path}. " \
            "Run build.rb with ESSENFONT_DUMP_CP_MAP=1 first."
    end

    data = JSON.parse(File.read(path))
    data.transform_values { |v| { label: v["label"].to_sym } }
  end
  private_class_method :load_cp_map

  def self.build_donor_metadata(manifest)
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
  private_class_method :build_donor_metadata

  def self.compute_block_donors(catalog, cp_map)
    catalog.all_blocks.each_with_object({}) do |b, h|
      cps_in_block = cp_map.keys.grep(b.first_cp..b.last_cp)

      donor_counts = cps_in_block.each_with_object(Hash.new(0)) do |cp, counts|
        counts[cp_map[cp][:label]] += 1
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
  private_class_method :compute_block_donors
end

require "time"

EmitProvenance.emit
