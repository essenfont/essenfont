# frozen_string_literal: true

module Essenfont
  module Otc
    module Naming
      FAMILY = "essenfont"
      SUBFAMILY = "Regular"
      COPYRIGHT = "OFL 1.1 + FSung-NC (CJK glyphs)"

      module_function

      def family
        FAMILY
      end

      def version_string
        Version::STRING
      end

      def version_major
        Version::STRING.split(".").map(&:to_i).fetch(0, 0)
      end

      def version_minor
        Version::STRING.split(".").map(&:to_i).fetch(1, 0)
      end
    end
  end
end
