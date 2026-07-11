# frozen_string_literal: true

module Essenfont
  module Manifest
    # One donor-font entry in the manifest. Thin struct over the YAML
    # hash — exposes typed accessors so callers don't reach into the
    # raw hash directly.
    #
    # Field names mirror the YAML keys (snake_case, Symbol keys).
    class Entry
      attr_reader :label, :family, :file, :sha256, :license, :url, :covers,
                  :codepoint_remap, :font_index, :type, :block, :enabled,
                  :version, :raw

      def initialize(hash)
        @raw = hash
        h = hash.transform_keys(&:to_sym)

        @label = h[:label]&.to_sym
        @family = h[:family] || @label&.to_s
        @file = h[:file]
        @sha256 = h[:sha256]
        @license = h[:license] || "OFL-1.1"
        @url = h[:url]
        @covers = h[:covers] || []
        @codepoint_remap = h[:codepoint_remap]
        @font_index = h[:font_index] || 0
        @type = (h[:type] || :font).to_sym
        @block = h[:block]
        @version = h[:version]
        @enabled = h.fetch(:enabled, true)
        @restrict_to_covers = !h[:restrict_to_covers].nil?
        freeze
      end

      def code_chart?
        @type == :code_chart
      end

      def remap?
        !@codepoint_remap.nil?
      end

      # When true, the donor's cmap is filtered at scan time to only
      # include codepoints that fall inside its declared `covers:` blocks.
      # Used for fonts whose cmap entries extend far beyond their intended
      # scope (e.g. FullSung's BMP ASCII glyphs contaminating non-CJK
      # assignments, or FSung-X whose cmap is in unofficial PUA positions).
      def restrict_to_covers?
        @restrict_to_covers
      end

      def to_h_for_json
        {
          label: @label,
          family: @family,
          file: @file,
          sha256: @sha256,
          license: @license,
          url: @url,
          covers: @covers,
          type: @type,
          block: @block,
          enabled: @enabled
        }.compact
      end
    end
  end
end
