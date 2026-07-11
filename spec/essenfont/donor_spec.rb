# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::Donor::Info do
  let(:fake_font) { Struct.new(:name).new("fake-font") }
  let(:fake_ufo) { Struct.new(:name).new("fake-ufo") }

  describe "#outline_source" do
    it "returns the UFO when both ufo and font are present" do
      donor = described_class.new(label: :test, font: fake_font, ufo: fake_ufo)
      expect(donor.outline_source).to be(fake_ufo)
    end

    it "returns the font when ufo is nil (CBDT path)" do
      donor = described_class.new(label: :test, font: fake_font)
      expect(donor.outline_source).to be(fake_font)
    end

    it "returns nil when both are nil" do
      donor = described_class.new(label: :test)
      expect(donor.outline_source).to be_nil
    end
  end

  describe "#cbdt?" do
    it "is true when font is present but ufo is nil" do
      donor = described_class.new(label: :test, font: fake_font)
      expect(donor).to be_cbdt
    end

    it "is false when ufo is present (outline path)" do
      donor = described_class.new(label: :test, font: fake_font, ufo: fake_ufo)
      expect(donor).not_to be_cbdt
    end

    it "is false when both are nil" do
      donor = described_class.new(label: :test)
      expect(donor).not_to be_cbdt
    end
  end

  describe "accessors" do
    it "exposes all fields via keyword_init struct" do
      donor = described_class.new(
        label: :noto_sans, font: fake_font, ufo: fake_ufo, file: "/path/font.ttf",
        coverage: { 0x41 => 1 }, remap: { 0xE000 => 0x11100 },
        entry: :manifest_entry, native_upm: 1000, scale_factor: 1.0
      )
      expect(donor.label).to eq(:noto_sans)
      expect(donor.font).to be(fake_font)
      expect(donor.ufo).to be(fake_ufo)
      expect(donor.file).to eq("/path/font.ttf")
      expect(donor.coverage).to eq({ 0x41 => 1 })
      expect(donor.remap).to eq({ 0xE000 => 0x11100 })
      expect(donor.entry).to eq(:manifest_entry)
      expect(donor.native_upm).to eq(1000)
      expect(donor.scale_factor).to eq(1.0)
    end
  end
end
