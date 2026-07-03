# frozen_string_literal: true

module Essenfont
  module Otc
    module Version
      STRING = File.read(File.expand_path("../../../VERSION", __dir__)).strip.freeze
    end
  end
end
