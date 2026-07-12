# frozen_string_literal: true

module Essenfont
  module Ufo
    # CoordinateClamp: detects and fixes glyphs whose coordinates exceed
    # the em-square by a large factor.
    #
    # Synthetic SVG-generated fonts (from Unicode code charts) can have
    # coordinates 2-11× larger than the declared UPM — fontisan's
    # SvgToGlyf doesn't scale SVG paths to the em-square. The UPM
    # normalization (Ufo::Normalization) trusts the font's reported
    # UPM and doesn't detect the mismatch.
    #
    # This module runs AFTER normalization. If any glyph coordinate
    # exceeds 1.5× the target UPM, it scales ALL coordinates so the
    # largest fits within the UPM. This is a safety net — the right
    # fix is at the SVG-to-glyf source, but this prevents extreme
    # coordinates from polluting the build output.
    #
    module CoordinateClamp
      THRESHOLD_FACTOR = 2.0

      module_function

      # @param ufo [Fontisan::Ufo::Font] the normalized UFO
      # @param target_upm [Integer] the target units-per-em (e.g., 1000)
      # @return [Fontisan::Ufo::Font] the same UFO, coordinates clamped
      def clamp!(ufo, target_upm:)
        threshold = target_upm * THRESHOLD_FACTOR
        max_abs = 0

        ufo.glyphs.each_value do |glyph|
          glyph.contours.each do |contour|
            contour.points.each do |point|
              max_abs = [max_abs, point.x.abs, point.y.abs].max
            end
          end
          glyph.components.each do |component|
            t = component.transformation
            next unless t
            max_abs = [max_abs, t.e.abs, t.f.abs].max
          end
        end

        return ufo if max_abs <= threshold

        scale = target_upm.to_f / max_abs
        warn "  coordinate clamp: max_abs=#{max_abs} > threshold=#{threshold.round(0)}, scaling by #{scale.round(4)}"

        ufo.glyphs.each_value do |glyph|
          clamp_glyph!(glyph, scale)
        end

        ufo
      end

      def clamp_glyph!(glyph, scale)
        glyph.contours.each do |contour|
          contour.points = contour.points.map do |point|
            Fontisan::Ufo::Point.new(
              x: (point.x * scale).round,
              y: (point.y * scale).round,
              type: point.type,
              smooth: point.smooth
            )
          end
        end

        glyph.width = (glyph.width * scale).round if glyph.width.is_a?(Numeric)

        glyph.components.map! do |component|
          next component unless component.transformation

          old = component.transformation
          scaled = Fontisan::Ufo::Transformation.new(
            a: old.a, b: old.b, c: old.c, d: old.d,
            e: (old.e * scale).round,
            f: (old.f * scale).round
          )
          Fontisan::Ufo::Component.new(
            base_glyph: component.base_glyph,
            transformation: scaled,
            identifier: component.identifier
          )
        end
      end
    end
  end
end
