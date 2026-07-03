# frozen_string_literal: true

module Essenfont
  module Otc
    module Errors
      class Base < StandardError; end
      class BuildError < Base; end
      class UnsupportedFormat < Base; end
    end
  end
end
