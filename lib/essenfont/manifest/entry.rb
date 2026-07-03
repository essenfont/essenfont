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
                  :raw

      def initialize(hash)
        @raw = hash
        @label = (hash["label"] || hash[:label])&.to_sym
        @family = hash["family"] || hash[:family] || @label&.to_s
        @file = hash["file"] || hash[:file]
        @sha256 = hash["sha256"] || hash[:sha256]
        @license = hash["license"] || hash[:license] || "OFL-1.1"
        @url = hash["url"] || hash[:url]
        @covers = hash["covers"] || hash[:covers] || []
        @codepoint_remap = hash["codepoint_remap"] || hash[:codepoint_remap]
        @font_index = hash["font_index"] || hash[:font_index] || 0
        @type = (hash["type"] || hash[:type] || :font).to_sym
        @block = hash["block"] || hash[:block]
        @enabled = hash.fetch("enabled", hash.fetch(:enabled, true))
        freeze
      end

      def code_chart?
        @type == :code_chart
      end

      def remap?
        !@codepoint_remap.nil?
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
