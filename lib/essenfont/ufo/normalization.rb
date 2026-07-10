# frozen_string_literal: true

module Essenfont
  module Ufo
    # Normalization: scale a Fontisan::Ufo::Font's coordinates from
    # the donor's native unitsPerEm to a target UPM (default 1000).
    #
    # Per-donor uniform scaling preserves the donor's internal design
    # proportions. Every glyph from the same donor gets the same scale
    # factor, so the donor's design system stays coherent. This is the
    # Noto Sans workflow applied to compiled donor fonts.
    #
    # Mutates the UFO in-place (Ruby ! convention). Callers that need
    # the original should pass a deep copy.
    #
    # @example Normalize a 2048-upm donor to 1000-upm
    #   Essenfont::Ufo::Normalization.apply!(ufo, target_upm: 1000)
    #
    class Normalization
      # Build-wide target unitsPerEm. Matches Essenfont::Otc::Naming's
      # verified value (scripts/verify.rb asserts head.unitsPerEm == 1000).
      DEFAULT_TARGET_UPM = 1000

      # Fontisan::Ufo::Info metric fields expressed in font units. These
      # scale linearly with UPM. Single source of truth: adding a new
      # metric field here is the only change needed to scale it.
      METRIC_FIELDS = %i[
        ascender
        descender
        cap_height
        x_height
        open_type_hhea_ascender
        open_type_hhea_descender
        open_type_hhea_line_gap
        open_type_vhea_ascender
        open_type_vhea_descender
        open_type_vhea_line_gap
      ].freeze

      private_constant :METRIC_FIELDS

      attr_reader :target_upm, :source_upm, :scale_factor

      # @param ufo [Fontisan::Ufo::Font] donor UFO to normalize
      # @param target_upm [Integer] desired unitsPerEm (default 1000)
      def initialize(ufo, target_upm: DEFAULT_TARGET_UPM)
        @ufo = ufo
        @target_upm = target_upm.to_i
        @source_upm = extract_source_upm
        @scale_factor = compute_scale_factor
      end

      # True when the donor's native UPM already matches the target.
      # When true, {#apply!} returns the UFO without mutation.
      def identity?
        scale_factor == 1.0
      end

      # Scale the UFO's coordinates + advance widths + font-info metrics
      # in-place. No-op when identity?.
      #
      # @return [Fontisan::Ufo::Font] the same UFO, mutated
      def apply!
        return ufo if identity?

        scale_font_info!
        scale_glyphs!

        ufo
      end

      # Class-level convenience: construct, apply, return the UFO.
      #
      # @param ufo [Fontisan::Ufo::Font]
      # @param target_upm [Integer]
      # @return [Fontisan::Ufo::Font] the normalized UFO
      def self.apply!(ufo, target_upm: DEFAULT_TARGET_UPM)
        new(ufo, target_upm: target_upm).apply!
      end

      private

      attr_reader :ufo

      def extract_source_upm
        info = ufo.info
        return DEFAULT_TARGET_UPM unless info

        value = info.units_per_em
        value && value.to_i.positive? ? value.to_i : DEFAULT_TARGET_UPM
      end

      def compute_scale_factor
        return 1.0 if source_upm.zero?

        target_upm.to_f / source_upm.to_f
      end

      # -- Font-info scaling ------------------------------------------------

      def scale_font_info!
        info = ufo.info
        return unless info

        info.units_per_em = target_upm
        METRIC_FIELDS.each { |field| scale_metric_field!(info, field) }
      end

      def scale_metric_field!(info, field)
        value = info.public_send(field)
        return unless value.is_a?(Numeric)

        info.public_send("#{field}=", scale_value(value))
      end

      # -- Per-glyph scaling ------------------------------------------------

      def scale_glyphs!
        ufo.glyphs.each_value { |glyph| scale_glyph!(glyph) }
      end

      def scale_glyph!(glyph)
        scale_advance!(glyph)
        scale_contours!(glyph)
        scale_components!(glyph)
      end

      def scale_advance!(glyph)
        glyph.width = scale_value(glyph.width) if numeric?(glyph.width)
        glyph.height = scale_value(glyph.height) if numeric?(glyph.height)
      end

      def scale_contours!(glyph)
        glyph.contours.each { |contour| scale_contour!(contour) }
      end

      def scale_contour!(contour)
        contour.points = contour.points.map { |point| scale_point(point) }
      end

      def scale_point(point)
        Fontisan::Ufo::Point.new(
          x: scale_value(point.x),
          y: scale_value(point.y),
          type: point.type,
          smooth: point.smooth
        )
      end

      # Components reference another glyph by name with a 2×3 affine
      # transform. Under uniform font scaling: the 2×2 matrix [a b c d]
      # stays the same (relative scale/rotation), only the translation
      # (e, f) scales — because the referenced glyph's outline is also
      # being scaled by the same factor.
      def scale_components!(glyph)
        return if glyph.components.empty?

        glyph.components.map! { |component| scale_component(component) }
      end

      def scale_component(component)
        return component unless component.transformation

        old = component.transformation
        scaled = Fontisan::Ufo::Transformation.new(
          a: old.a, b: old.b, c: old.c, d: old.d,
          e: scale_value(old.e),
          f: scale_value(old.f)
        )
        Fontisan::Ufo::Component.new(
          base_glyph: component.base_glyph,
          transformation: scaled,
          identifier: component.identifier
        )
      end

      # -- Value scaling ----------------------------------------------------

      def scale_value(value)
        return 0 if value.nil?
        return value if value.zero?

        (value.to_f * scale_factor).round
      end

      def numeric?(value)
        value.is_a?(Numeric)
      end
    end
  end
end
