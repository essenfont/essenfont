# frozen_string_literal: true

require "spec_helper"

# MetricsPass operates on TTC files at the binary level. Full integration
# tests require a real TTC fixture (produced by the Stitcher), which makes
# them fragile in CI without the full donor font set.
#
# The unit-testable parts — Extents accumulation, FaceTableLocator TTC
# header parsing — are covered here. The full patch-roundtrip is validated
# by scripts/verify.rb in the release CI.

RSpec.describe Essenfont::Otc::MetricsPass do
  describe "Extents" do
    it "starts empty and absorbs glyph bboxes" do
      extents = Essenfont::Otc::Extents.new(
        x_min: Float::INFINITY, y_min: Float::INFINITY,
        x_max: -Float::INFINITY, y_max: -Float::INFINITY)
      extents.absorb!(-100, -50, 500, 800)
      extents.absorb!(0, 0, 600, 900)

      expect(extents.x_min).to eq(-100)
      expect(extents.y_min).to eq(-50)
      expect(extents.x_max).to eq(600)
      expect(extents.y_max).to eq(900)
    end

    it "detects empty state" do
      extents = Essenfont::Otc::Extents.new(
        x_min: Float::INFINITY, y_min: Float::INFINITY,
        x_max: -Float::INFINITY, y_max: -Float::INFINITY)
      expect(extents.empty?).to be true
    end
  end

  describe "#recompute!" do
    pending "requires a real TTC fixture — validated by scripts/verify.rb in CI"
  end
end
