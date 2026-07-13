# frozen_string_literal: true

module Essenfont
  module Ufo
    # AdvanceWidthNormalizer: sets every glyph's advance width to the
    # target UPM.
    #
    # essenfont is a universal fallback font — it renders characters
    # the primary font doesn't have. Different donors use wildly
    # different advance-width conventions (observed range: 20..4637
    # in a 1000-UPM face). When mixed in one face, this produces
    # visual inconsistency — some characters are 2x wider than others.
    #
    # Normalizing all advance widths to UPM ensures every character
    # occupies exactly 1 em of horizontal space, matching the
    # convention used by the Noto Sans family for ideographic
    # characters.
    #
    module AdvanceWidthNormalizer
      module_function

      # @param ufo [Fontisan::Ufo::Font] the UFO to normalize
      # @param target_upm [Integer] the target units-per-em
      def normalize!(ufo, target_upm:)
        ufo.glyphs.each_value do |glyph|
          glyph.width = target_upm if glyph.width.is_a?(Numeric)
        end
      end
    end
  end
end
