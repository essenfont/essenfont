# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::CpMap do
  let(:raw_map) do
    {
      0x41 => { label: :noto, gid: 1 },
      0x4E00 => { label: :fsung_m, gid: 1 },
      0xE000 => { label: :pua_donor, gid: 5 },       # PUA — should be filtered
      0xF0000 => { label: :pua_donor, gid: 7 },      # PUA-A — should be filtered
      0x10030 => { label: :lentariso, gid: 1 },
      0x20000 => { label: :fsung_2, gid: 1 }
    }
  end

  let(:cp_map) { described_class.new(raw_map) }

  describe "#donor_labels" do
    it "collapses to the {cp => label} shape" do
      labels = cp_map.donor_labels
      expect(labels[0x41]).to eq(:noto)
      expect(labels[0x4E00]).to eq(:fsung_m)
    end
  end

  describe "#size + #keys" do
    it "counts codepoints" do
      expect(cp_map.size).to eq(6)
      expect(cp_map.keys).to include(0x41, 0x4E00)
    end
  end

  describe "#filter_reserved" do
    it "drops PUA + Surrogates + Specials codepoints" do
      filtered = cp_map.filter_reserved
      expect(filtered.size).to eq(4) # 6 - 2 PUA
      expect(filtered.keys).not_to include(0xE000, 0xF0000)
    end
  end

  describe "#backfill_cc_cf" do
    it "maps C0 controls to gid 0 of the first donor" do
      backfilled = cp_map.backfill_cc_cf(:noto)
      expect(backfilled[0x0000]).to eq(label: :noto, gid: 0)
      expect(backfilled[0x000D]).to eq(label: :noto, gid: 0) # CR
      expect(backfilled[0x009F]).to eq(label: :noto, gid: 0) # C1
      expect(backfilled[0xFEFF]).to eq(label: :noto, gid: 0) # ZWNBSP
    end

    it "preserves existing cps" do
      backfilled = cp_map.backfill_cc_cf(:noto)
      expect(backfilled[0x41]).to eq(label: :noto, gid: 1)
    end
  end

  describe "#remap" do
    it "moves donor assignment from source cps to target cps" do
      mapping = { 0x41 => 0x11DB0 } # ASCII A → Tolong Siki
      remapped = cp_map.remap(mapping)
      expect(remapped[0x11DB0]).to eq(label: :noto, gid: 1)
      expect(remapped[0x41]).to be_nil
    end
  end

  describe "#by_plane" do
    it "groups codepoints by Unicode plane number" do
      expect(cp_map.by_plane).to eq({
        0 => [0x41, 0x4E00, 0xE000],
        1 => [0x10030],
        2 => [0x20000],
        15 => [0xF0000]
      })
    end
  end

  describe "#by_donor" do
    it "groups codepoints by donor label" do
      by_donor = cp_map.by_donor
      expect(by_donor[:noto]).to include(0x41)
      expect(by_donor[:fsung_2]).to eq([0x20000])
    end
  end

  describe ".from_donors" do
    # Structs stand in for Fontisan::TrueTypeFont at the table-lookup
    # boundary CpMap.from_donors touches. Using keyword_init lets us
    # pass the table map by name — same shape as a real font's #table.
    let(:font_class) do
      Struct.new(:tables, keyword_init: true) do
        def table(name)
          tables[name]
        end
      end
    end

    let(:cmap_class) do
      Struct.new(:mappings, keyword_init: true) do
        def unicode_mappings
          mappings
        end
      end
    end

    let(:outline_font) do
      font_class.new(tables: {
        "glyf" => Object.new, "CFF " => nil, "CFF2" => nil,
        "CBDT" => nil, "CBLC" => nil,
        "cmap" => cmap_class.new(mappings: { 0x41 => 1 }),
      })
    end

    let(:cbdt_only_font) do
      font_class.new(tables: {
        "glyf" => nil, "CFF " => nil, "CFF2" => nil,
        "CBDT" => Object.new, "CBLC" => Object.new,
        "cmap" => cmap_class.new(mappings: { 0x1F600 => 1, 0x1F601 => 2 }),
      })
    end

    let(:donors) do
      {
        emoji: Essenfont::Donor::Info.new(label: :emoji, font: cbdt_only_font, coverage: {}.to_set, remap: nil),
        outline: Essenfont::Donor::Info.new(label: :outline, font: outline_font, coverage: { 0x41 => 1 }, remap: nil)
      }
    end

    it "scans outline-eligible donors into the cp_map" do
      cp_map = described_class.from_donors(donors)
      expect(cp_map.keys).to include(0x41)
    end

    it "skips CBDT-only donors (delegates to OutlinePolicy)" do
      cp_map = described_class.from_donors(donors)
      expect(cp_map.keys).not_to include(0x1F600, 0x1F601)
    end

    it "records the donor label and gid for each codepoint" do
      cp_map = described_class.from_donors(donors)
      expect(cp_map[0x41]).to eq(label: :outline, gid: 1)
    end

    it "keeps the first donor's assignment when several cover the same cp" do
      second_outline = font_class.new(tables: {
        "glyf" => Object.new, "CFF " => nil, "CFF2" => nil,
        "CBDT" => nil, "CBLC" => nil,
        "cmap" => cmap_class.new(mappings: { 0x41 => 9 }),
      })
      donors[:second] = Essenfont::Donor::Info.new(label: :second, font: second_outline, coverage: { 0x41 => 9 }, remap: nil)

      cp_map = described_class.from_donors(donors)
      expect(cp_map[0x41]).to eq(label: :outline, gid: 1)
    end
  end

  describe "immutability" do
    it "is frozen on construction" do
      expect(cp_map).to be_frozen
      expect(cp_map.map).to be_frozen
    end
  end
end
