# frozen_string_literal: true

module Essenfont
  module Otc
    module Errors
      class Base < StandardError
        attr_reader :codepoint, :donor, :block

        def initialize(message = nil, codepoint: nil, donor: nil, block: nil)
          @codepoint = codepoint
          @donor = donor
          @block = block
          parts = [message]
          parts << "cp=#{format_cp(codepoint)}" if codepoint
          parts << "donor=#{donor.inspect}" if donor
          parts << "block=#{block.inspect}" if block
          super(parts.compact.join(" · "))
        end

        private

        def format_cp(cp)
          return cp.inspect unless cp.is_a?(Integer)

          "U+#{cp.to_s(16).upcase}"
        end
      end

      class BuildError < Base; end
      class UnsupportedFormat < Base; end

      # Build-pipeline-specific errors. Carrying structured context lets
      # CI rescue + categorize instead of grepping the message.
      class DonorMissing < Base; end
      class DonorShaMismatch < Base; end
      class DonorFileInvalid < Base; end
      class CoverageGateFailed < Base; end
      class CollectionValidation < Base; end
      class ManifestMissing < Base; end
    end
  end
end
