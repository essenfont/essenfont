# frozen_string_literal: true

module Essenfont
  # CpMap: the per-codepoint donor assignment map.
  #
  # Owns the {cp => {label:, gid:}} shape used throughout the build.
  # Provides shape-conversion views for downstream consumers:
  #   - .donor_labels   → {cp => label}              (fontisan PartitionStrategy)
  #   - .with_gids      → {cp => {label:, gid:}}     (Stitcher internals)
  #   - .filter_pua     → CpMap with PUA/Surrogate/Specials removed
  #   - .backfill_cc_cf → CpMap with C0/C1/Cf codepoints mapped to .notdef
  #
  # Replaces the inline transform_values calls scattered across
  # lib/essenfont/otc/build.rb and scripts/build.rb.
  class CpMap
    # Reserved ranges excluded by .filter_reserved (matches Unicode
    # "non-character" zones — PUA, Surrogates, Specials). Sourced from
    # the UCD; intentionally inline so the cap on `non-commercial
    # glyph` filtering is local.
    RESERVED_RANGES = [
      (0xE000..0xF8FF),     # Private Use Area
      (0xF0000..0xFFFFD),   # Supplementary Private Use Area-A
      (0x100000..0x10FFFD), # Supplementary Private Use Area-B
      (0xD800..0xDFFF),     # Surrogates
      (0xFFF0..0xFFFF),     # Specials
      (0x1FFFE..0x1FFFF), (0x2FFFE..0x2FFFF), (0x3FFFE..0x3FFFF),
      (0x4FFFE..0x4FFFF), (0x5FFFE..0x5FFFF), (0x6FFFE..0x6FFFF),
      (0x7FFFE..0x7FFFF), (0x8FFFE..0x8FFFF), (0x9FFFE..0x9FFFF),
      (0xAFFFE..0xAFFFF), (0xBFFFE..0xBFFFF), (0xCFFFE..0xCFFFF),
      (0xDFFFE..0xDFFFF), (0xEFFFE..0xEFFFF), (0xFFFFE..0xFFFFF),
      (0x10FFFE..0x10FFFF)
    ].freeze

    # C0/C1/Cf codepoints that no donor covers; .backfill_cc_cf maps
    # them to gid 0 (the .notdef glyph) of the first donor.
    BACKFILL_CC_CF = (
      (0x0000..0x001F).to_a +     # C0 controls
      (0x007F..0x009F).to_a +     # DEL + C1
      (0x200B..0x200F).to_a +     # ZWSP / ZWNJ / ZWJ marks
      (0x202A..0x202E).to_a +     # bidi LRM/RLM marks
      (0x2060..0x2064).to_a +     # word joiner
      [0xFEFF]                    # BOM/ZWNBSP
    ).freeze

    attr_reader :map

    def initialize(map = {})
      @map = map.transform_values do |v|
        {
          label: v.fetch(:label) || v.fetch("label"),
          gid: v.fetch(:gid) || v.fetch("gid")
        }
      end.freeze
      freeze
    end

    # Build a CpMap by scanning donor fonts' cmaps.
    #
    # CBDT-only donors (color bitmap emoji fonts without a glyf table)
    # are deliberately excluded from the outline cp_map. Their cmap
    # entries point at bitmap glyphs that have no outline representation;
    # including them here causes the Stitcher's add_all_cbdt_glyphs path
    # to allocate empty glyf slots for those codepoints in every face.
    # The resulting cmap entries resolve to .notdef and produce
    # degenerate WOFF2 subsets that Chrome's OTS rejects.
    #
    # CBDT glyph data propagates separately via the Stitcher's
    # propagate_cbdt_tables mechanism; the outline cp_map should reflect
    # only codepoints whose donors can actually supply glyf outlines.
    def self.from_donors(donors)
      new_from_scan(donors)
    end

    def self.new_from_scan(donors)
      map = {}
      donors.each_value do |d|
        next if cbdt_only?(d[:font])

        mappings = scan_cmap(d[:font])
        mappings.each do |cp, gid|
          map[cp] ||= { label: d[:label], gid: gid }
        end
      end
      new(map)
    end

    # True if the donor font carries color bitmaps (CBDT/CBLC) but no
    # glyf or CFF table — i.e. it cannot contribute outline data.
    def self.cbdt_only?(font)
      return false unless font

      font.table("CBDT") && font.table("CBLC") &&
        font.table("glyf").nil? &&
        font.table("CFF ").nil? &&
        font.table("CFF2").nil?
    end
    private_class_method :cbdt_only?

    def self.scan_cmap(font)
      return {} unless font

      cmap = font.table("cmap")
      return {} unless cmap

      cmap.unicode_mappings || {}
    rescue StandardError
      {}
    end
    private_class_method :scan_cmap

    # {cp => donor_label} view, for fontisan PartitionStrategy::ByPlane
    # which expects the simpler shape.
    def donor_labels
      @map.transform_values { |v| v[:label] }
    end

    # {cp => {label:, gid:}} view (the original shape).
    def with_gids
      @map
    end

    def size
      @map.size
    end

    def keys
      @map.keys
    end

    def [](cp)
      @map[cp]
    end

    def each(&block)
      @map.each(&block)
    end

    # Returns a new CpMap with PUA / Surrogates / Specials codepoints dropped.
    def filter_reserved
      filtered = @map.reject { |cp, _| reserved?(cp) }
      CpMap.new(filtered)
    end

    # Returns a new CpMap with C0/C1/Cf codepoints (the BACKFILL_CC_CF list)
    # mapped to gid 0 of the first donor, if no donor covers them.
    def backfill_cc_cf(first_donor_label)
      new_map = @map.dup
      BACKFILL_CC_CF.each do |cp|
        new_map[cp] ||= { label: first_donor_label, gid: 0 }
      end
      CpMap.new(new_map)
    end

    # Apply a {source => target} remap to the cp_map. Source cps are
    # removed, target cps take their donor assignment.
    def remap(mapping)
      new_map = @map.dup
      mapping.each do |src, target|
        info = new_map.delete(src)
        next unless info

        new_map[target] = info
      end
      CpMap.new(new_map)
    end

    # Codepoints grouped by plane number.
    def by_plane
      @map.keys.group_by { |cp| cp >> 16 }
    end

    # Codepoints grouped by donor label.
    def by_donor
      @map.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(cp, info), h|
        h[info[:label]] << cp
      end
    end

    private

    def reserved?(cp)
      RESERVED_RANGES.any? { |r| r.cover?(cp) }
    end
  end
end
