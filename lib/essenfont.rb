# frozen_string_literal: true

require "fontisan"
require "ucode"

module Essenfont
  autoload :Manifest,      "essenfont/manifest"
  autoload :CpMap,         "essenfont/cp_map"
  autoload :CoverageReport,"essenfont/coverage_report"
  autoload :CoverageGate,  "essenfont/coverage_gate"
  autoload :Donor,         "essenfont/donor"
  autoload :DonorLoader,   "essenfont/donor_loader"
  autoload :FontMagic,     "essenfont/font_magic"
  autoload :OutlinePolicy, "essenfont/outline_policy"
  autoload :Pipeline,      "essenfont/pipeline"
  autoload :Release,       "essenfont/release"
  autoload :Remap,         "essenfont/remap"
  autoload :UcodeRef,      "essenfont/ucode_ref"
  autoload :Otc,           "essenfont/otc"
  autoload :Ufo,           "essenfont/ufo"
  autoload :BuildCache,    "essenfont/build_cache"
end
