# frozen_string_literal: true

module Essenfont
  # OutlinePolicy: classifies a loaded donor font's fitness for the
  # outline-stitching path.
  #
  # Single responsibility: decide which donors CpMap.from_donors should
  # scan. CBDT-only color-bitmap fonts (Noto Color Emoji etc.) carry
  # cmap entries that point at bitmap glyphs with no outline
  # representation; their inclusion pollutes every face with empty
  # .notdef slots and produces degenerate WOFF2 subsets that Chrome's
  # OTS rejects. CBDT data propagates separately via the Stitcher's
  # +propagate_cbdt_tables+ mechanism.
  #
  # Future ineligible categories (variable-only without a default
  # instance, chromatic-only, etc.) extend this module — not CpMap.
  module OutlinePolicy
    module_function

    # Filter a donors hash to those whose fonts can supply outlines.
    # Preserves the input shape ({label => donor_hash}).
    def outline_eligible(donors)
      donors.select { |_, d| contributes_outlines?(d[:font]) }
    end

    # True if the font has at least one outline table and is not in a
    # known ineligibility category.
    def contributes_outlines?(font)
      return false unless font
      return false if cbdt_only?(font)

      true
    end

    # True if the font carries color bitmaps (CBDT/CBLC) but no glyf,
    # CFF, or CFF2 outline table.
    def cbdt_only?(font)
      return false unless font

      has_cbdt = !font.table("CBDT").nil? && !font.table("CBLC").nil?
      has_outline = !font.table("glyf").nil? || !font.table("CFF ").nil? || !font.table("CFF2").nil?

      has_cbdt && !has_outline
    end
  end
end
