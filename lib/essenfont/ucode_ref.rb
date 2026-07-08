# frozen_string_literal: true

require "ucode"

module Essenfont
  # UcodeRef: typed bridge to the ucode gem's Unicode metadata.
  #
  # Replaces inline `File.read("/Users/.../ucode/output/blocks/index.json")`
  # calls that silently fell back to a 10-block subset on non-dev
  # machines. The ucode gem ships the canonical 346-block list as Ruby
  # constants — no path concerns, no I/O, no silent degradation.
  #
  # Also centralizes the small adapter logic needed to translate
  # ucode's plane/block objects into the shapes the build expects
  # (e.g., {block_id => [first_cp, last_cp]} for the coverage gate).
  module UcodeRef
    module_function

    # The Unicode version pinned by the ucode gem (e.g., "17.0.0").
    def unicode_version
      Ucode::Unicode.unicode_version
    end

    # Number of assigned codepoints in this Unicode version.
    def assigned_count
      Ucode::Unicode.assigned_count
    end

    # The catalog (one per Unicode version).
    def catalog
      Ucode::Unicode.for_version
    end

    # Block-id → [first_cp, last_cp] for the coverage gate.
    # Keyed by the canonical ucode block id (e.g., "CJK_Unified_Ideographs").
    # @return [Hash<String, Array<Integer, Integer>>]
    def block_ranges
      @block_ranges ||= catalog.all_blocks.to_h do |b|
        [b.id, [b.first_cp, b.last_cp]]
      end.freeze
    end

    # Range for a single block, or nil if not found.
    def block_range(block_id)
      block_ranges[block_id.to_s]
    end

    # All blocks in a given plane number.
    def blocks_in_plane(plane_number)
      catalog.blocks_in_plane(plane_number)
    end

    # Plane short-name (:BMP, :SMP, :SIP, :TIP, :SSP) for a codepoint.
    def plane_short_name(cp)
      plane = catalog.find_plane_by_codepoint(cp)
      return nil unless plane

      plane.short_name
    end

    # Codepoint ranges Unicode reserves for non-character use and that
    # essenfont excludes from the build: PUA (user-defined), Supplementary
    # PUA-A/B, Surrogates, Specials, and the last two codepoints of every
    # plane (the XFFFE/XFFFF non-characters). Single source of truth —
    # CpMap and any other consumer delegates here.
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

    # Whether a codepoint lives in a Unicode-reserved range we exclude
    # from the build (PUA, Surrogates, Specials, per-plane noncharacters).
    def reserved?(cp)
      RESERVED_RANGES.any? { |r| r.cover?(cp) }
    end

    # The 5 Unicode planes that carry assigned characters (BMP/SMP/SIP/TIP/SSP).
    def assigned_planes
      [0, 1, 2, 3, 14]
    end
  end
end
