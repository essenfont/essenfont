# frozen_string_literal: true

module Essenfont
  module Otc
    module Naming
      FAMILY = "essenfont"
      VERSION = "0.1"
      SUBFAMILY = "Regular"
      COPYRIGHT = "OFL 1.1 + FSung-NC (CJK glyphs)"

      module_function

      def family
        FAMILY
      end

      def version_string
        VERSION
      end

      def version_major
        major, _minor = VERSION.split(".").map(&:to_i)
        major || 0
      end

      def version_minor
        _major, minor = VERSION.split(".").map(&:to_i)
        minor || 0
      end
    end
  end
end
