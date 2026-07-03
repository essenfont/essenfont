# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::UcodeRef do
  it "exposes the Unicode version from the ucode gem" do
    expect(described_class.unicode_version).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "exposes a positive assigned-count" do
    expect(described_class.assigned_count).to be > 100_000
  end

  describe ".block_ranges" do
    it "returns 346 block ranges" do
      expect(described_class.block_ranges.size).to be > 300
    end

    it "maps block id → [first_cp, last_cp]" do
      range = described_class.block_range("CJK_Unified_Ideographs")
      expect(range).to eq([0x4E00, 0x9FFF])
    end

    it "returns nil for unknown block id" do
      expect(described_class.block_range("Nope_Block")).to be_nil
    end
  end

  describe ".reserved?" do
    it "flags PUA codepoints" do
      expect(described_class.reserved?(0xE000)).to be true  # BMP PUA
      expect(described_class.reserved?(0xF0000)).to be true # SPUA-A
    end

    it "flags surrogates" do
      expect(described_class.reserved?(0xD800)).to be true
    end

    it "allows assigned plane codepoints" do
      expect(described_class.reserved?(0x41)).to be false
      expect(described_class.reserved?(0x4E00)).to be false
    end
  end

  describe ".assigned_planes" do
    it "lists the 5 planes essenfont ships" do
      expect(described_class.assigned_planes).to eq([0, 1, 2, 3, 14])
    end
  end
end
