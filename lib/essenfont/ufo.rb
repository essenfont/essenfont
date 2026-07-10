# frozen_string_literal: true

module Essenfont
  # UFO-driven build layer.
  #
  # Owns the boundary between compiled donor fonts (TTF/OTF/TTC) and
  # the normalized UFO representation the Stitcher consumes. Each
  # donor is converted to a Fontisan::Ufo::Font via
  # Fontisan::Ufo::Convert::FromBinData, then normalized to the
  # build's target unitsPerEm (1000) by {Essenfont::Ufo::Normalization}.
  #
  # Single responsibility: coordinate UFO conversion + normalization.
  # Glyph-level data mutations live in theNormalization class; table
  # reading/writing lives in fontisan; this namespace just wires them.
  module Ufo
    autoload :Normalization, "essenfont/ufo/normalization"
  end
end
