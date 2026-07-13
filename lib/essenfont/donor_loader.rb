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
  # The returned Donor::Info carries either +font+ (CBDT path) or
  # +ufo+ (outline path). Callers (CpMap, Otc::Build) access the
  # stitcher source via `donor.outline_source` (ufo || font).
  class DonorLoader
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
      return warn_skip(entry, "not a valid font (magic bytes mismatch)") unless Essenfont::FontMagic.valid?(resolved)
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
      Essenfont::Donor::Info.new(
        label: entry.label, font: font, file: resolved,
        coverage: coverage, remap: remap, entry: entry
      )
    end

    # -- Outline (UFO) path ------------------------------------------------

    def load_outline_donor(entry, font, resolved, remap)
      ufo, native_upm, scale_factor = convert_and_measure(font, glyph_scale: entry.glyph_scale)

      coverage = scan_ufo_coverage(ufo, entry: entry)
      report_load(entry, coverage, remap,
                  mode: :ufo,
                  native_upm: native_upm,
                  scale_factor: scale_factor)

      Essenfont::Donor::Info.new(
        label: entry.label, font: font, ufo: ufo, file: resolved,
        coverage: coverage, remap: remap, entry: entry,
        native_upm: native_upm, scale_factor: scale_factor
      )
    end

    # Convert font → UFO, normalize, measure UPM + scale factor.
    # For CFF-based fonts, fills in contours that fontisan's UFO
    # converter stubs out (extract_cff_glyphs is a TODO in 0.4.23).
    # For glyf-based fonts, fills in compound (composite) glyphs that
    # the converter silently drops (only SimpleGlyph is handled).
    # Returns [ufo, native_upm, scale_factor].
    def convert_and_measure(font, glyph_scale: 1.0)
      ufo = convert_to_ufo(font)
      fill_cff_outlines_if_needed(font, ufo)
      fill_compound_glyphs_if_needed(font, ufo)

      native_upm = read_ufo_upm(ufo)

      normalization = Essenfont::Ufo::Normalization.new(ufo, target_upm: target_upm)
      normalization.apply! unless normalization.identity?

      Essenfont::Ufo::CoordinateClamp.clamp!(ufo, target_upm: target_upm)

      scale_glyphs(ufo, factor: glyph_scale) if glyph_scale != 1.0

      [ufo, native_upm, normalization.scale_factor * glyph_scale]
    end

    def convert_to_ufo(font)
      Fontisan::Ufo::Convert::FromBinData.convert(font)
    end

    # fontisan's FromBinData.extract_cff_glyphs is a stub — it creates
    # UFO glyphs with names + widths but zero contours. CffOutlineFiller
    # bridges OutlineExtractor (which CAN parse CFF) into the UFO.
    def fill_cff_outlines_if_needed(font, ufo)
      return unless font.respond_to?(:cff?) ? font.cff? : false
      return if ufo.glyphs.values.all? { |g| !g.contours.nil? && !g.contours.empty? }

      Essenfont::Ufo::CffOutlineFiller.fill!(font, ufo)
    end

    # fontisan's FromBinData.extract_truetype_glyphs only handles
    # SimpleGlyph — CompoundGlyph instances get empty contours.
    # CompoundGlyphFiller uses the Stitcher Source's own compound
    # resolution to populate them before normalization.
    def fill_compound_glyphs_if_needed(font, ufo)
      return unless font.respond_to?(:has_table?) && font.has_table?("glyf")
      return if ufo.glyphs.values.all? { |g| !g.contours.nil? && !g.contours.empty? }

      Essenfont::Ufo::CompoundGlyphFiller.fill!(font, ufo)
    end

    # Apply a per-donor uniform scale to glyph outlines and advance
    # widths. Used when a donor's design size doesn't match the
    # target — e.g. UniHieroglyphica glyphs are ~19% smaller than
    # Noto Sans, so glyph_scale: 1.187 scales them up.
    def scale_glyphs(ufo, factor:)
      ufo.glyphs.each_value do |glyph|
        glyph.width = (glyph.width * factor).round if glyph.width.is_a?(Numeric)
        glyph.contours.each do |contour|
          contour.points = contour.points.map do |pt|
            Fontisan::Ufo::Point.new(
              x: (pt.x * factor).round,
              y: (pt.y * factor).round,
              type: pt.type,
              smooth: pt.smooth
            )
          end
        end
      end
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

    # -- Remap loading (delegates to Essenfont::Remap) --------------------

    def load_remap(spec)
      Essenfont::Remap.load(spec, search_dirs: [@remap_dir])
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
