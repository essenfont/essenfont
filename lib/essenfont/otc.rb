# frozen_string_literal: true

module Essenfont
  module Otc
    autoload :Build,       "essenfont/otc/build"
    autoload :Errors,      "essenfont/otc/errors"
    autoload :MetricsPass, "essenfont/otc/metrics_pass"
    autoload :Naming,      "essenfont/otc/naming"
    autoload :Validator,   "essenfont/otc/validator"
    autoload :Version,     "essenfont/otc/version"
  end
end
