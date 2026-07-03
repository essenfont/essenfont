#!/usr/bin/env ruby
# frozen_string_literal: true

# Emit per-codepoint + per-block donor provenance for the website.
#
# Reads:
#   cp_map.json              (per-cp donor; dumped by build.rb with
#                             ESSENFONT_DUMP_CP_MAP=1)
#   sources/manifest.yml     (donor registry)
#   public/unicode-blocks.json (block ranges; from ucode)
#
# Writes:
#   provenance.json   — donors + blocks + per-cp attribution (large)
#   provenance.json.gz — compressed
#
# The site loads provenance.json.gz lazily and uses it to drive the
# /provenance page + per-codepoint donor attribution on UnicodeCharPage.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "yaml"
require "zlib"
require "fileutils"

module EmitProvenance
  ROOT = File.expand_path("..", __dir__)

  def self.emit
    cp_map = load_cp_map
    donors_meta = load_donor_metadata
    blocks = load_blocks

    cps_by_donor = group_cps_by_donor(cp_map)
    blocks_meta = compute_block_donors(blocks, cp_map)

    manifest = {
      essenfont_version: Essenfont::Otc::Version::STRING,
      ucd_version: Ucode::Unicode.unicode_version,
      generated_at: Time.now.utc.iso8601,
      donor_count: donors_meta.size,
      codepoint_count: cp_map.size,
      donors: donors_meta,
      blocks: blocks_meta,
      codepoints: cp_map.transform_values { |v| { donor: v[:label] } }
    }

    json = JSON.generate(manifest)
    File.write("provenance.json", json)
    Zlib::GzipWriter.open("provenance.json.gz") { |gz| gz.write(json) }

    puts "wrote provenance.json (#{(json.bytesize / 1024.0 / 1024).round(1)} MB)"
    puts "wrote provenance.json.gz (#{(File.size("provenance.json.gz") / 1024.0 / 1024).round(1)} MB)"
    puts "  #{donors_meta.size} donors, #{blocks_meta.size} blocks, #{cp_map.size} cps"
  end

  def self.load_cp_map
    path = File.join(ROOT, "cp_map.json")
    unless File.exist?(path)
      warn "ERROR: #{path} not found. Run build.rb with ESSENFONT_DUMP_CP_MAP=1 first."
      exit 1
    end
    data = JSON.parse(File.read(path))
    data.transform_values { |v| { label: (v["label"] || v[:label]).to_sym } }
  end

  def self.load_donor_metadata
    manifest = YAML.safe_load(File.read(File.join(ROOT, "sources", "manifest.yml")))
    manifest["donors"].each_with_object({}) do |d, h|
      label = d["label"].to_sym
      h[label] = {
        family: d["family"] || d["label"],
        license: d["license"] || "OFL-1.1",
        version: d["version"],
        url: d["url"],
        sha256: d["sha256"]
      }
    end
  end

  def self.load_blocks
    path = File.join(ROOT, "..", "essenfont.github.io", "public", "unicode-blocks.json")
    path = "/Users/mulgogi/src/fontist/ucode/output/blocks/index.json" unless File.exist?(path)
    unless File.exist?(path)
      warn "ERROR: unicode-blocks.json not found at #{path}"
      exit 1
    end
    JSON.parse(File.read(path))
  end

  def self.group_cps_by_donor(cp_map)
    cp_map.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(cp, info), h|
      h[info[:label]] << cp
    end
  end

  # For each block, find the primary donor (most cps in the block)
  # and all contributing donors.
  def self.compute_block_donors(blocks, cp_map)
    blocks.each_with_object({}) do |b, h|
      block_id = b["id"]
      first = b["first_cp"]
      last = b["last_cp"]
      cps_in_block = cp_map.keys.select { |cp| cp >= first && cp <= last }

      donor_counts = cps_in_block.each_with_object(Hash.new(0)) do |cp, counts|
        counts[cp_map[cp][:label]] += 1
      end

      primary = donor_counts.max_by { |_, c| c }&.first

      h[block_id] = {
        first_cp: sprintf("0x%X", first),
        last_cp: sprintf("0x%X", last),
        primary_donor: primary,
        donors: donor_counts.keys,
        donor_counts: donor_counts.transform_keys(&:to_s),
        codepoint_count: cps_in_block.size
      }
    end
  end
end

require "time"
require "essenfont"
require "ucode"

EmitProvenance.emit
