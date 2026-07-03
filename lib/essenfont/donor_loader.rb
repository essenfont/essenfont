# frozen_string_literal: true

require "digest"

module Essenfont
  # DonorLoader: turns Manifest entries into loaded donor fonts.
  #
  # Owns the boundary between "manifest entry" (data) and "loaded donor
  # font" (a Fontisan::TrueTypeFont + its scanned cmap). Encapsulates
  # the four-step load dance: resolve path → verify magic bytes → verify
  # sha256 → load via Fontisan → return {font:, label:, coverage:, ...}.
  #
  # Replaces EssenfontBuild.load_donors in scripts/build.rb.
  class DonorLoader
    MAGIC_BYTES = [
      "\x00\x01\x00\x00",  # TTF
      "OTTO",              # OTF (CFF)
      "true",              # TrueType (Apple variant)
      "ttcf",              # TTC
      "wOFF",              # WOFF
      "wOF2",              # WOFF2
      "\x00\x01\x00\x00".b # TTF (binary)
    ].freeze

    attr_reader :manifest, :donor_dir, :remap_dir

    # @param manifest [Essenfont::Manifest::Collection]
    # @param donor_dir [String] path to donor font files (defaults to references/input-fonts)
    # @param remap_dir [String] path to remap files (defaults to sources/remaps)
    def initialize(manifest:, donor_dir: DonorLoader.default_donor_dir, remap_dir: DonorLoader.default_remap_dir)
      @manifest = manifest
      @donor_dir = donor_dir
      @remap_dir = remap_dir
    end

    # Load every active donor entry. Returns {label => donor_hash}.
    # @return [Hash<Symbol, Hash>]
    def load_all
      manifest.active.each_with_object({}) do |entry, loaded|
        donor = load_one(entry)
        loaded[entry.label] = donor if donor
      end
    end

    # Load a single entry, returning nil (with a warning) if anything fails.
    def load_one(entry)
      resolved = resolve_path(entry)
      return warn_skip(entry, "file not resolved") unless resolved

      return warn_skip(entry, "missing on disk: #{resolved}") unless File.exist?(resolved)
      return warn_skip(entry, "not a valid font (magic bytes mismatch)") unless valid_magic?(resolved)
      return warn_skip(entry, "sha256 mismatch") unless valid_sha256?(resolved, entry.sha256, entry.label)

      font = load_font(resolved, entry)
      return warn_skip(entry, "font loader raised") unless font

      coverage = scan_coverage(font)
      coverage = apply_remap_to_coverage(coverage, entry, font) if entry.remap?

      report_load(entry, coverage)
      { label: entry.label, font: font, file: resolved, coverage: coverage,
        entry: entry }
    rescue StandardError => e
      warn_skip(entry, "exception: #{e.message}")
    end

    def self.default_donor_dir
      File.expand_path("../../references/input-fonts", __dir__)
    end

    def self.default_remap_dir
      File.expand_path("../../sources/remaps", __dir__)
    end

    private

    def resolve_path(entry)
      return entry.file if entry.file && File.exist?(entry.file)
      return entry.file if entry.code_chart? && (synthetic = resolve_synthetic(entry))

      candidate = File.join(@donor_dir, File.basename(entry.file.to_s))
      return candidate if File.exist?(candidate)

      nil
    end

    def resolve_synthetic(entry)
      return nil unless entry.block

      synthetic = File.join(@donor_dir, ".generated", "svg-donors",
                            "#{entry.block.tr('-', '_')}.ttf")
      return synthetic if File.exist?(synthetic)

      nil
    end

    def valid_magic?(path)
      return false unless File.exist?(path) && File.size(path) > 16

      magic = File.binread(path, 4)
      return true if MAGIC_BYTES.include?(magic)

      return true if File.binread(path, 1).getbyte(0) == 0x80 # PFB

      warn "    first 4 bytes: #{magic.inspect} — not a font magic"
      false
    rescue StandardError
      false
    end

    def valid_sha256?(path, expected, label)
      return true if expected.nil? || expected == "TBD"

      actual = Digest::SHA256.file(path).hexdigest
      return true if actual == expected.downcase

      warn "    sha256 mismatch for #{label}:"
      warn "      expected: #{expected}"
      warn "      actual:   #{actual}"
      false
    end

    def load_font(path, entry)
      Fontisan::FontLoader.load(path, font_index: entry.font_index)
    end

    def scan_coverage(font)
      cmap = font.table("cmap")
      return {} unless cmap

      cmap.unicode_mappings || {}
    rescue StandardError
      {}
    end

    def apply_remap_to_coverage(coverage, entry, font)
      remap = load_remap(entry.codepoint_remap)
      return coverage unless remap && !remap.empty?

      original_size = coverage.size
      remapped = coverage.each_with_object({}) do |(src, gid), h|
        target = remap[src]
        h[target] = gid if target
      end
      mutate_cmap_with_remap!(font, remap)
      warn "    remapped: #{original_size} → #{remapped.size} codepoints"
      remapped
    end

    def load_remap(spec)
      path = resolve_remap_path(spec)
      return nil unless path && File.exist?(path)

      data = YAML.safe_load(File.read(path))
      mappings = data.fetch("mappings", [])
      return nil if mappings.empty?

      mappings.each_with_object({}) do |m, h|
        h[m.fetch("from")] = m.fetch("to")
      end
    end

    def resolve_remap_path(spec)
      return spec if File.exist?(spec)

      candidate = File.join(@remap_dir, File.basename(spec))
      candidate if File.exist?(candidate)
    end

    # Apply a remap to the font's cmap in-memory. The unicode_mappings
    # hash is cached on the cmap table object; this mutation persists
    # across the Stitcher's later reads.
    def mutate_cmap_with_remap!(font, remap)
      cmap = font.table("cmap")
      return unless cmap

      maps = cmap.unicode_mappings
      return unless maps

      new_maps = remap.each_with_object({}) do |(src, target), h|
        gid = maps[src]
        h[target] = gid if gid
      end
      maps.replace(new_maps)
    end

    def report_load(entry, coverage)
      puts "  loaded #{entry.label}: #{coverage.size} codepoints#{' (remapped)' if entry.remap?}"
    end

    def warn_skip(entry, reason)
      warn "skip: donor #{entry.label} — #{reason}"
      nil
    end
  end
end
