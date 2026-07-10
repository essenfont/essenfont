# frozen_string_literal: true

module Essenfont
  # Donor: the loaded-donor representation the Stitcher consumes.
  #
  # Replaces the shapeless Hash that DonorLoader previously returned
  # (keys accessed via d[:label], d[:ufo] || d[:font], etc.). A typed
  # value object concentrates the donor shape in one place — field
  # changes no longer require grepping callers, and the outline-source
  # fallback is encapsulated in #outline_source instead of repeated
  # at every call site.
  module Donor
    Info = Struct.new(
      :label, :font, :ufo, :file, :coverage, :remap, :entry,
      :native_upm, :scale_factor,
      keyword_init: true
    ) do
      # The source the Stitcher should consume: the normalized UFO when
      # available, the raw font otherwise. CBDT-only donors have no UFO
      # — their glyph data lives in CBDT/CBLC bitmap tables propagated
      # by the Stitcher as raw bytes.
      def outline_source
        ufo || font
      end

      # True when this donor was loaded via the CBDT bitmap path
      # (no UFO conversion). OutlinePolicy delegates here.
      def cbdt?
        ufo.nil? && !font.nil?
      end
    end
  end
end
