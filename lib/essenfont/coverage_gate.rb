# frozen_string_literal: true

module Essenfont
  # CoverageGate: validates that manifest entries declaring `covers:`
  # actually have cmap coverage for those blocks.
  #
  # Single responsibility: produce a list of declared-but-empty coverage
  # failures. Callers decide what to do with the list (.validate! raises,
  # .failures returns).
  #
  # Skips:
  #   - Donors that weren't loaded (e.g., FSung is path_local_only)
  #   - Remapped donors (their raw cmap is at non-canonical cps; the
  #     remap happens at stitch time via add_source(remap:))
  #
  # Replaces the duplicated validate_coverage_gates that lived in both
  # scripts/build.rb (raising) and scripts/release.rb (warning). Both
  # now delegate here.
  class CoverageGate
    Failure = Struct.new(:label, :block, :range, keyword_init: true) do
      def message
        "#{label}: declares covers:#{block} but cmap has 0 codepoints in " \
          "U+#{range[0].to_s(16).upcase}..U+#{range[1].to_s(16).upcase}"
      end
    end

    attr_reader :manifest, :donors

    def initialize(manifest:, donors:)
      @manifest = manifest
      @donors = donors
    end

    # Returns an Array of Failure records. Empty if everything checks out.
    def failures
      manifest.active.flat_map { |entry| entry_failures(entry) }.compact
    end

    # Raises CoverageGateFailed if any declared covers: block has 0 cmap
    # coverage. Otherwise returns true.
    def validate!
      fails = failures
      return true if fails.empty?

      raise Essenfont::Otc::Errors::CoverageGateFailed,
            "declared covers: blocks have 0 cmap coverage:\n" \
            "#{fails.map { |f| "  - #{f.message}" }.join("\n")}"
    end

    private

    def entry_failures(entry)
      donor = donors[entry.label]
      return [] unless donor
      return [] if donor[:remap]

      (entry.covers || []).filter_map do |block|
        range = UcodeRef.block_range(block)
        next nil unless range

        count = donor[:coverage].keys.count { |cp| cp.between?(range[0], range[1]) }
        next nil if count.positive?

        Failure.new(label: entry.label, block: block, range: range)
      end
    end
  end
end
