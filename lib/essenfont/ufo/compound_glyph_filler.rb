# frozen_string_literal: true

module Essenfont
  module Ufo
    # CompoundGlyphFiller: fills empty UFO contours for compound (composite)
    # glyphs that fontisan's UFO converter silently drops.
    #
    # fontisan's FromBinData.extract_truetype_glyphs only handles
    # SimpleGlyph — CompoundGlyph instances get empty contours in the
    # UFO. The Stitcher's Source class has full compound resolution
    # for TTF sources (flatten_compound_into) but the UFO source path
    # reads empty glyphs directly.
    #
    # This module bridges the gap: it uses the Source's own TTF
    # extraction (which resolves compounds) to populate empty UFO
    # glyphs. Called before normalization, so the compound contours
    # are at the source UPM and get scaled correctly.
    #
    module CompoundGlyphFiller
      module_function

      # @param font [Fontisan::SfntFont] the loaded glyf-based donor font
      # @param ufo [Fontisan::Ufo::Font] the stub UFO (empty contours for compounds)
      # @return [Fontisan::Ufo::Font] the same UFO, now with real contours
      def fill!(font, ufo)
        return ufo unless font.respond_to?(:has_table?) && font.has_table?("glyf")

        source = Fontisan::Stitcher::Source.new(font)
        filled = 0

        ufo.glyphs.each_with_index do |(_name, ufo_glyph), gid|
          next unless ufo_glyph.contours.nil? || ufo_glyph.contours.empty?

          resolved = source.glyph_for_gid(gid)
          next unless resolved&.contours&.any?

          resolved.contours.each { |c| ufo_glyph.add_contour(c) }
          filled += 1
        end

        if filled.positive?
          warn "  compound glyph fill: #{filled} glyphs populated"
        end
        ufo
      end
    end
  end
end
