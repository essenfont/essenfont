# frozen_string_literal: true

require "json"
require "time"

module Essenfont
  # Release namespace — artifact emitters for the release pipeline.
  #
  # Each module owns one release artifact (coverage manifest, provenance,
  # license pack, SVG exports, npm package). Both the standalone scripts
  # in scripts/emit_*.rb and scripts/release.rb delegate here —
  # previously each had its own copy of the logic, and they had drifted.
  module Release
    autoload :CoverageManifest, "essenfont/release/coverage_manifest"
    autoload :Provenance,       "essenfont/release/provenance"
    autoload :LicensePack,      "essenfont/release/license_pack"
    autoload :SvgExports,       "essenfont/release/svg_exports"
    autoload :NpmPackage,       "essenfont/release/npm_package"

    PLANES = %i[BMP SMP SIP TIP SSP].freeze
    PLANE_RANGES = {
      BMP: "U+0000-FFFF",
      SMP: "U+10000-1FFFF",
      SIP: "U+20000-2FFFF",
      TIP: "U+30000-3FFFF",
      SSP: "U+E0000-EFFFF"
    }.freeze
  end
end
