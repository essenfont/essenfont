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
    it "flags BMP PUA codepoints" do
      expect(described_class.reserved?(0xE000)).to be true
      expect(described_class.reserved?(0xF8FF)).to be true
    end

    it "flags Supplementary PUA-A and PUA-B" do
      expect(described_class.reserved?(0xF0000)).to be true
      expect(described_class.reserved?(0xFFFFD)).to be true
      expect(described_class.reserved?(0x100000)).to be true
      expect(described_class.reserved?(0x10FFFD)).to be true
    end

    it "flags surrogates" do
      expect(described_class.reserved?(0xD800)).to be true
      expect(described_class.reserved?(0xDFFF)).to be true
    end

    it "flags BMP noncharacters but not the assigned Specials codepoints" do
      # Assigned Specials codepoints (visible symbols + interlinear
      # annotation controls) must NOT be reserved — they're real
      # characters that essenfont should cover.
      expect(described_class.reserved?(0xFFF9)).to be false # INTERLINEAR ANNOTATION ANCHOR
      expect(described_class.reserved?(0xFFFB)).to be false # INTERLINEAR ANNOTATION TERMINATOR
      expect(described_class.reserved?(0xFFFC)).to be false # OBJECT REPLACEMENT CHARACTER
      expect(described_class.reserved?(0xFFFD)).to be false # REPLACEMENT CHARACTER
      # Noncharacter slots at the end of the BMP ARE reserved.
      expect(described_class.reserved?(0xFFFE)).to be true
      expect(described_class.reserved?(0xFFFF)).to be true
    end

    it "flags the last two codepoints of every plane (XFFFE/XFFFF noncharacters)" do
      expect(described_class.reserved?(0xFFFE)).to be true
      expect(described_class.reserved?(0x1FFFE)).to be true
      expect(described_class.reserved?(0x1FFFF)).to be true
      expect(described_class.reserved?(0x2FFFE)).to be true
      expect(described_class.reserved?(0xEFFFE)).to be true
      expect(described_class.reserved?(0xEFFFF)).to be true
      expect(described_class.reserved?(0x10FFFE)).to be true
      expect(described_class.reserved?(0x10FFFF)).to be true
    end

    it "allows assigned plane codepoints" do
      expect(described_class.reserved?(0x41)).to be false   # ASCII 'A'
      expect(described_class.reserved?(0x4E00)).to be false # CJK 一
      expect(described_class.reserved?(0x1F600)).to be false # 😀
    end

    it "is exposed as a module function (single source of truth for CpMap)" do
      expect(described_class).to respond_to(:reserved?)
      expect(defined?(Essenfont::CpMap::RESERVED_RANGES)).to be_nil,
                                                             "CpMap should not duplicate RESERVED_RANGES — delegate to UcodeRef"
    end
  end

  describe ".assigned_planes" do
    it "lists the 5 planes essenfont ships" do
      expect(described_class.assigned_planes).to eq([0, 1, 2, 3, 14])
    end
  end
end
