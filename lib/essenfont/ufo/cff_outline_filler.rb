# frozen_string_literal: true

module Essenfont
  module Ufo
    # CffOutlineFiller: fills empty UFO contours for CFF-based donor fonts.
    #
    # fontisan's UFO converter (FromBinData) has a stubbed extract_cff_glyphs
    # — it creates glyphs with names + advance widths but ZERO contours
    # (TODO in fontisan 0.4.23). This module bridges the gap by using
    # fontisan's OutlineExtractor (which CAN parse CFF charstrings) to
    # populate the contours after the stub conversion.
    #
    # Without this, every CFF-based OTF donor (Noto Serif Tangut, etc.)
    # silently produces empty glyphs in the output — cmap entries exist
    # but glyph outlines have 0 contours.
    #
    module CffOutlineFiller
      module_function

      # @param font [Fontisan::SfntFont] the loaded CFF-based donor font
      # @param ufo [Fontisan::Ufo::Font] the stub UFO (empty contours)
      # @return [Fontisan::Ufo::Font] the same UFO, now with real contours
      def fill!(font, ufo)
        extractor = Fontisan::OutlineExtractor.new(font)
        filled = 0

        ufo.glyphs.each_with_index do |(_name, glyph), gid|
          next unless glyph.contours.nil? || glyph.contours.empty?

          outline = extractor.extract(gid)
          next unless outline&.contours

          outline.contours.each do |contour_points|
            ufo_points = convert_contour(contour_points)
            glyph.add_contour(Fontisan::Ufo::Contour.new(ufo_points)) unless ufo_points.empty?
          end
          filled += 1
        end

        warn "  CFF outline fill: #{filled} glyphs populated" if filled.positive?
        ufo
      end

      # Convert OutlineExtractor contour points ({x:, y:, on_curve:})
      # to UFO points (Fontisan::Ufo::Point with type: :move/:line/:curve/:offcurve).
      #
      # GLIF point type rules for cubic Bézier:
      # - First point of a contour: :move (if on_curve) or :offcurve
      # - off_curve point: :offcurve
      # - on_curve after on_curve: :line
      # - on_curve after off_curve: :curve (end of cubic segment)
      def convert_contour(points)
        return [] if points.nil? || points.empty?

        points.each_with_index.map do |pt, i|
          type = point_type(points, i)
          Fontisan::Ufo::Point.new(
            x: pt[:x].to_i,
            y: pt[:y].to_i,
            type: type
          )
        end
      end

      def point_type(points, i)
        return points[0][:on_curve] ? :move : :offcurve if i.zero?

        current_on = points[i][:on_curve]
        prev_on = points[i - 1][:on_curve]

        if !current_on
          :offcurve
        elsif prev_on
          :line
        else
          :curve
        end
      end
    end
  end
end
