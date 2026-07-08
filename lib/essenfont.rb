# frozen_string_literal: true

require "fontisan"
require "ucode"

module Essenfont
  autoload :Manifest,      "essenfont/manifest"
  autoload :CpMap,         "essenfont/cp_map"
  autoload :CoverageGate,  "essenfont/coverage_gate"
  autoload :DonorLoader,   "essenfont/donor_loader"
  autoload :OutlinePolicy, "essenfont/outline_policy"
  autoload :UcodeRef,      "essenfont/ucode_ref"
  autoload :Otc,           "essenfont/otc"
end
