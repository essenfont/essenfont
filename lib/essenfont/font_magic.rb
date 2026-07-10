# frozen_string_literal: true

module Essenfont
  # FontMagic: single source of truth for font-file magic-byte validation.
  #
  # DonorLoader and donor_audit.rb previously each maintained their own
  # list — and they had drifted (DonorLoader had 7 entries, donor_audit
  # had 6). Adding a new font format meant editing both; forgetting one
  # silently rejected valid donors.
  module FontMagic
    MAGIC_BYTES = [
      "\x00\x01\x00\x00",  # TTF
      "OTTO",               # OTF (CFF)
      "true",               # TrueType (Apple variant)
      "ttcf",               # TTC / OTC
      "wOFF",               # WOFF
      "wOF2",               # WOFF2
      "\x00\x01\x00\x00".b  # TTF (binary)
    ].freeze

    PFB_PREFIX_BYTE = 0x80

    module_function

    def valid?(path)
      return false unless File.exist?(path) && File.size(path) > 16

      magic = File.binread(path, 4)
      return true if MAGIC_BYTES.include?(magic)
      return true if magic.getbyte(0) == PFB_PREFIX_BYTE

      false
    rescue StandardError
      false
    end
  end
end
