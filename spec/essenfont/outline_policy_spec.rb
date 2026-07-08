# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::OutlinePolicy do
  # Structs stand in for Fontisan::TrueTypeFont at the table-lookup
  # boundary OutlinePolicy touches. Real fonts have the same shape:
  # `font.table(name)` returns a truthy table object or nil.
  let(:font_class) do
    Struct.new(:tables, keyword_init: true) do
      def table(name)
        tables[name]
      end
    end
  end

  let(:outline_font) do
    font_class.new(tables: { "glyf" => Object.new, "CFF " => nil, "CFF2" => nil,
                             "CBDT" => nil, "CBLC" => nil })
  end

  let(:cbdt_only_font) do
    font_class.new(tables: { "glyf" => nil, "CFF " => nil, "CFF2" => nil,
                             "CBDT" => Object.new, "CBLC" => Object.new })
  end

  let(:cff_font) do
    font_class.new(tables: { "glyf" => nil, "CFF " => Object.new, "CFF2" => nil,
                             "CBDT" => nil, "CBLC" => nil })
  end

  describe ".contributes_outlines?" do
    it "returns true for a glyf outline font" do
      expect(described_class.contributes_outlines?(outline_font)).to be true
    end

    it "returns true for a CFF outline font" do
      expect(described_class.contributes_outlines?(cff_font)).to be true
    end

    it "returns false for a CBDT-only color bitmap font" do
      expect(described_class.contributes_outlines?(cbdt_only_font)).to be false
    end

    it "returns false for nil" do
      expect(described_class.contributes_outlines?(nil)).to be false
    end
  end

  describe ".cbdt_only?" do
    it "detects CBDT/CBLC with no outline tables" do
      expect(described_class.cbdt_only?(cbdt_only_font)).to be true
    end

    it "returns false when glyf is present" do
      expect(described_class.cbdt_only?(outline_font)).to be false
    end

    it "returns false when CFF is present" do
      expect(described_class.cbdt_only?(cff_font)).to be false
    end

    it "returns false for nil" do
      expect(described_class.cbdt_only?(nil)).to be false
    end
  end

  describe ".outline_eligible" do
    let(:donors) do
      {
        emoji: { label: :emoji, font: cbdt_only_font },
        outline: { label: :outline, font: outline_font },
        cff: { label: :cff, font: cff_font }
      }
    end

    it "keeps donors whose fonts can supply outlines" do
      filtered = described_class.outline_eligible(donors)
      expect(filtered.keys).to contain_exactly(:outline, :cff)
    end

    it "drops CBDT-only donors" do
      filtered = described_class.outline_eligible(donors)
      expect(filtered.keys).not_to include(:emoji)
    end

    it "preserves the donor-hash shape (label => donor_hash)" do
      filtered = described_class.outline_eligible(donors)
      expect(filtered[:outline]).to eq donors[:outline]
    end

    it "returns a new hash (does not mutate the input)" do
      original = donors.dup
      described_class.outline_eligible(donors)
      expect(donors).to eq original
    end
  end
end
