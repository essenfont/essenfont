# frozen_string_literal: true

module Essenfont
  # Pipeline: the build-preparation invariant — manifest → donors →
  # validate → cp_map. Previously duplicated between scripts/build.rb
  # and scripts/release.rb, where the validation order could drift.
  #
  # Pipeline.build concentrates the sequence in one place. Both scripts
  # call it; the caller adds its own puts/progress messages.
  #
  Pipeline = Struct.new(:manifest, :donors, :cp_map, keyword_init: true) do
    # Load manifest, load donors, validate coverage gates, build cp_map.
    # Raises BuildError if no donors loaded, CoverageGateFailed if any
    # declared covers: block has 0 cmap coverage.
    #
    # @return [Pipeline] with manifest, donors, and cp_map populated
    def self.build
      manifest = Manifest.load
      donors = DonorLoader.new(manifest: manifest).load_all
      raise Otc::Errors::BuildError,
            "no donor fonts loaded — check sources/manifest.yml + references/input-fonts/" if donors.empty?

      CoverageGate.new(manifest:, donors:).validate!
      cp_map = CpMap.build_from(donors)
      new(manifest:, donors:, cp_map:)
    end
  end
end
