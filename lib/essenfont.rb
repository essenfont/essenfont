# frozen_string_literal: true

require "fontisan"
require "ucode"

module Essenfont
  autoload :Manifest,    "essenfont/manifest"
  autoload :CpMap,       "essenfont/cp_map"
  autoload :DonorLoader, "essenfont/donor_loader"
  autoload :UcodeRef,    "essenfont/ucode_ref"
  autoload :Otc,         "essenfont/otc"
end
