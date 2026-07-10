# frozen_string_literal: true

require "spec_helper"

# Minimal font-like struct for testing CpMap's fallback scan path.
# Not a double — a real data container that answers the same protocol
# CpMap's scan_cmap uses.
module CpMapTestHelpers
  FontStub = Struct.new(:cmap) do
    def table(name)
      return nil unless name == "cmap"

      Struct.new(:unicode_mappings).new(cmap)
    end
  end
  private_constant :FontStub
end

RSpec.describe Essenfont::CpMap, "restrict_to_covers enforcement" do
  include CpMapTestHelpers

  it "uses d[:coverage] instead of rescanning d[:font]" do
    # leaky donor has Basic Latin in its RAW cmap, but :coverage (filtered)
    # only includes CJK. CpMap must read :coverage, not the raw cmap.
    leaky_raw_cmap = { 0x41 => 1, 0x42 => 2, 0x4E00 => 3 }
    clean_raw_cmap = { 0x41 => 1 }

    donors = {
      "leaky" => {
        label: "leaky",
        font: FontStub.new(leaky_raw_cmap),
        coverage: { 0x4E00 => 3 },
        remap: nil
      },
      "clean" => {
        label: "clean",
        font: FontStub.new(clean_raw_cmap),
        coverage: { 0x41 => 1 },
        remap: nil
      }
    }

    cp_map = Essenfont::CpMap.from_donors(donors)

    # If CpMap read the RAW cmap, leaky would win 0x41 (first-wins).
    # Reading :coverage, clean wins 0x41.
    expect(cp_map[0x41][:label]).to eq("clean")
    expect(cp_map[0x4E00][:label]).to eq("leaky")
  end

  it "falls back to scan_cmap when :coverage is absent" do
    donors = {
      "raw" => {
        label: "raw",
        font: FontStub.new({ 0x41 => 1 }),
        remap: nil
      }
    }

    cp_map = Essenfont::CpMap.from_donors(donors)
    expect(cp_map[0x41][:label]).to eq("raw")
  end
end
