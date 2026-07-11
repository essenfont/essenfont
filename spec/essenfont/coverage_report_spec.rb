# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::CoverageReport do
  # Lightweight stand-ins for ucode Block + Catalog objects. Not doubles —
  # real Structs that answer the same protocol CoverageReport touches.
  let(:block_class) { Struct.new(:id, :name, :first_cp, :last_cp, keyword_init: true) }
  let(:catalog_class) { Struct.new(:all_blocks, keyword_init: true) }

  let(:blocks) do
    [
      block_class.new(id: "Basic_Latin", name: "Basic Latin", first_cp: 0x41, last_cp: 0x7A),
      block_class.new(id: "Small_Block", name: "Small", first_cp: 0x100, last_cp: 0x10F),
      block_class.new(id: "CJK", name: "CJK Unified", first_cp: 0x4E00, last_cp: 0x4E09)
    ]
  end

  let(:catalog) { catalog_class.new(all_blocks: blocks) }

  describe "#per_block" do
    it "computes covered/total/pct per block" do
      report = described_class.new((0x41..0x50).to_a, catalog: catalog)

      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:covered]).to eq(16) # 0x41..0x50
      expect(basic[:total]).to eq(58)  # 0x41..0x7A inclusive
      expect(basic[:first]).to eq(0x41)
      expect(basic[:last]).to eq(0x7A)
    end

    it "classifies EMPTY when no codepoints covered" do
      report = described_class.new([], catalog: catalog)
      statuses = report.per_block.map { |r| [r[:id], r[:status]] }.to_h
      expect(statuses["Basic_Latin"]).to eq("EMPTY")
      expect(statuses["Small_Block"]).to eq("EMPTY")
      expect(statuses["CJK"]).to eq("EMPTY")
    end

    it "classifies COMPLETE when every codepoint in the block is covered" do
      report = described_class.new((0x100..0x10F).to_a, catalog: catalog)
      small = report.per_block.find { |r| r[:id] == "Small_Block" }
      expect(small[:status]).to eq("COMPLETE")
      expect(small[:covered]).to eq(small[:total])
    end

    it "classifies PARTIAL when some but <50% covered" do
      report = described_class.new([0x42], catalog: catalog)
      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:status]).to eq("PARTIAL")
    end

    it "classifies MOSTLY when >=50% covered" do
      cps = (0x41..0x5D).to_a # 29 of 58 = 50%
      report = described_class.new(cps, catalog: catalog)
      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:status]).to eq("MOSTLY")
    end

    it "classifies FULL when >=95% covered" do
      cps = (0x41..0x78).to_a # 56 of 58 = 96.5%
      report = described_class.new(cps, catalog: catalog)
      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:pct]).to be >= 95
      expect(basic[:status]).to eq("FULL")
    end

    it "sorts results by first codepoint" do
      report = described_class.new([], catalog: catalog)
      firsts = report.per_block.map { |r| r[:first] }
      expect(firsts).to eq(firsts.sort)
    end

    it "includes range string" do
      report = described_class.new([], catalog: catalog)
      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:range]).to eq("U+41..U+7A")
    end
  end

  describe "#summary" do
    it "counts blocks and statuses" do
      report = described_class.new((0x41..0x5D).to_a, catalog: catalog)
      summary = report.summary

      expect(summary[:blocks]).to eq(3)
      expect(summary[:assigned_blocks]).to eq(3)
      expect(summary[:reserved_blocks]).to eq(0)
      expect(summary[:empty]).to eq(2) # Small_Block + CJK have 0 covered
    end

    it "sums covered and total across assigned blocks" do
      report = described_class.new((0x41..0x7A).to_a + [0x4E00], catalog: catalog)
      summary = report.summary

      # Basic_Latin: 58 covered / 58 total (0x41..0x7A)
      # Small_Block: 0 / 16 (0x100..0x10F)
      # CJK: 1 / 10 (0x4E00..0x4E09)
      expect(summary[:covered]).to eq(58 + 0 + 1)
      expect(summary[:total]).to eq(58 + 16 + 10)
    end

    it "computes overall pct" do
      report = described_class.new((0x41..0x7A).to_a, catalog: catalog)
      summary = report.summary
      expected = (58.0 / 84 * 100).round(4)
      expect(summary[:pct]).to eq(expected)
    end
  end

  describe "with assigned_filter" do
    it "uses the filter as the denominator" do
      assigned = (0x41..0x45).to_set
      report = described_class.new([0x41, 0x42], catalog: catalog, assigned_filter: assigned)

      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:total]).to eq(5)
      expect(basic[:covered]).to eq(2)
    end

    it "counts RESERVED when filter makes total zero" do
      assigned = Set.new
      report = described_class.new([0x41], catalog: catalog, assigned_filter: assigned)

      basic = report.per_block.find { |r| r[:id] == "Basic_Latin" }
      expect(basic[:total]).to eq(0)
      expect(basic[:status]).to eq("RESERVED")
    end
  end
end
