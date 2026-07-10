# frozen_string_literal: true

require "digest"

module Essenfont
  # DonorLoader: turns Manifest entries into loaded donor fonts.
  #
  # Owns the boundary between "manifest entry" (data) and the
  # donor representation the Stitcher consumes. Each non-CBDT donor
  # is loaded as a raw font → converted to UFO via Fontisan's
  # FromBinData converter → normalized to the build's target
  # unitsPerEm by Essenfont::Ufo::Normalization. CBDT-only donors
  # (color-bitmap emoji) bypass UFO conversion — their glyph data
  # lives in CBDT/CBLC tables that the Stitcher propagates as raw
  # bytes.
  #
  # The returned donor hash carries either +:font+ (CBDT path) or
  # +:ufo+ (outline path). Callers (CpMap, Otc::Build) handle both
  # via `donor[:ufo] || donor[:font]`.
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

    attr_reader :manifest, :donor_dir, :remap_dir, :target_upm

    # @param manifest [Essenfont::Manifest::Collection]
    # @param donor_dir [String] path to donor font files
    # @param remap_dir [String] path to remap files
    # @param target_upm [Integer] desired unitsPerEm for UFO normalization
    def initialize(manifest:,
                   donor_dir: DonorLoader.default_donor_dir,
                   remap_dir: DonorLoader.default_remap_dir,
                   target_upm: Essenfont::Ufo::Normalization::DEFAULT_TARGET_UPM)
      @manifest = manifest
      @donor_dir = donor_dir
      @remap_dir = remap_dir
      @target_upm = target_upm.to_i
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
    #
    # For non-CBDT donors: converts to UFO, normalizes to target_upm.
    # For CBDT-only donors: returns the raw font (bitmap path).
    def load_one(entry)
      resolved = resolve_path(entry)
      return warn_skip(entry, "file not resolved") unless resolved

      return warn_skip(entry, "missing on disk: #{resolved}") unless File.exist?(resolved)
      return warn_skip(entry, "not a valid font (magic bytes mismatch)") unless valid_magic?(resolved)
      return warn_skip(entry, "sha256 mismatch") unless valid_sha256?(resolved, entry.sha256, entry.label)

      font = load_font(resolved, entry)
      return warn_skip(entry, "font loader raised") unless font

      remap = entry.remap? ? load_remap(entry.codepoint_remap) : nil

      if OutlinePolicy.cbdt_only?(font)
        load_cbdt_donor(entry, font, resolved, remap)
      else
        load_outline_donor(entry, font, resolved, remap)
      end
    rescue StandardError => e
      warn_skip(entry, "exception: #{e.message}")
    end

    class << self
      def default_donor_dir
        File.expand_path("../../references/input-fonts", __dir__)
      end

      def default_remap_dir
        File.expand_path("../../sources/remaps", __dir__)
      end
    end

    private

    # -- CBDT path ---------------------------------------------------------

    def load_cbdt_donor(entry, font, resolved, remap)
      coverage = scan_font_coverage(font, entry: entry)
      report_load(entry, coverage, remap, mode: :cbdt)
      { label: entry.label, font: font, file: resolved, coverage: coverage,
        remap: remap, entry: entry }
    end

    # -- Outline (UFO) path ------------------------------------------------

    def load_outline_donor(entry, font, resolved, remap)
      ufo = convert_to_ufo(font)
      native_upm = read_ufo_upm(ufo)

      normalization = Essenfont::Ufo::Normalization.new(ufo, target_upm: target_upm)
      normalization.apply! unless normalization.identity?

      coverage = scan_ufo_coverage(ufo, entry: entry)
      report_load(entry, coverage, remap,
                  mode: :ufo,
                  native_upm: native_upm,
                  scale_factor: normalization.scale_factor)

      { label: entry.label, font: font, ufo: ufo, file: resolved, coverage: coverage,
        remap: remap, entry: entry,
        native_upm: native_upm,
        scale_factor: normalization.scale_factor }
    end

    def convert_to_ufo(font)
      Fontisan::Ufo::Convert::FromBinData.convert(font)
    end

    def read_ufo_upm(ufo)
      info = ufo.info
      return target_upm unless info

      value = info.units_per_em
      value && value.to_i.positive? ? value.to_i : target_upm
    end

    # -- Path resolution ---------------------------------------------------

    def resolve_path(entry)
      return entry.file if entry.file && File.exist?(entry.file)
      return resolve_synthetic(entry) if entry.code_chart? && entry.block

      candidate = File.join(@donor_dir, File.basename(entry.file.to_s))
      return candidate if File.exist?(candidate)

      nil
    end

    def resolve_synthetic(entry)
      synthetic = File.join(@donor_dir, ".generated", "svg-donors",
                            "#{entry.block.tr('-', '_')}.ttf")
      File.exist?(synthetic) ? synthetic : nil
    end

    # -- Validation --------------------------------------------------------

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

    # -- Coverage scanning -------------------------------------------------

    # Reads a raw font's cmap → {cp => gid}. Applies restrict_to_covers.
    def scan_font_coverage(font, entry:)
      cmap = font.table("cmap")
      return {} unless cmap

      apply_covers_filter(cmap.unicode_mappings || {}, entry)
    rescue StandardError
      {}
    end

    # Reads a UFO's glyph unicodes → {cp => gid}. Applies restrict_to_covers.
    def scan_ufo_coverage(ufo, entry:)
      mappings = {}
      ufo.glyphs.each_with_index do |(_name, glyph), gid|
        glyph.unicodes.each { |cp| mappings[cp] = gid }
      end

      apply_covers_filter(mappings, entry)
    rescue StandardError
      {}
    end

    # Single source of truth for the restrict_to_covers filter. Both
    # scan_font_coverage and scan_ufo_coverage delegate here.
    def apply_covers_filter(mappings, entry)
      return mappings unless entry&.restrict_to_covers?

      ranges = (entry.covers || []).filter_map { |b| Essenfont::UcodeRef.block_range(b) }
      return {} if ranges.empty?

      mappings.select { |cp, _| ranges.any? { |from, to| cp.between?(from, to) } }
    end

    # -- Remap loading -----------------------------------------------------

    def load_remap(spec)
      path = resolve_remap_path(spec)
      return nil unless path && File.exist?(path)

      data = YAML.safe_load_file(path)
      mappings = data.fetch("mappings", [])
      return nil if mappings.empty?

      mappings.to_h do |m|
        [m.fetch("from"), m.fetch("to")]
      end
    end

    def resolve_remap_path(spec)
      return spec if File.exist?(spec)

      candidate = File.join(@remap_dir, File.basename(spec))
      File.exist?(candidate) ? candidate : nil
    end

    # -- Reporting ---------------------------------------------------------

    def report_load(entry, coverage, remap, mode:, native_upm: nil, scale_factor: nil)
      suffix = remap&.any? ? " (remapped: #{remap.size} cps)" : ""
      upm_info = if mode == :ufo && scale_factor && scale_factor != 1.0
                   " [upm #{native_upm}→#{target_upm} ×#{scale_factor.round(4)}]"
                 else
                   ""
                 end
      puts "  loaded #{entry.label} (#{mode}): #{coverage.size} cps#{suffix}#{upm_info}"
    end

    def warn_skip(entry, reason)
      warn "skip: donor #{entry.label} — #{reason}"
      nil
    end
  end
end
