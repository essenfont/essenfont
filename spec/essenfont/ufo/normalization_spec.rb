# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::Ufo::Normalization do
  let(:target_upm) { 1000 }

  describe "#scale_factor" do
    it "returns 1.0 for a 1000-upm UFO" do
      ufo = build_ufo(units_per_em: 1000)
      norm = described_class.new(ufo, target_upm: target_upm)
      expect(norm.scale_factor).to eq(1.0)
    end

    it "returns ~0.9766 for a 1024-upm UFO" do
      ufo = build_ufo(units_per_em: 1024)
      norm = described_class.new(ufo, target_upm: target_upm)
      expect(norm.scale_factor).to be_within(0.0001).of(0.9765625)
    end

    it "returns ~0.4883 for a 2048-upm UFO" do
      ufo = build_ufo(units_per_em: 2048)
      norm = described_class.new(ufo, target_upm: target_upm)
      expect(norm.scale_factor).to be_within(0.0001).of(0.48828125)
    end

    it "returns ~0.4167 for a 2400-upm UFO" do
      ufo = build_ufo(units_per_em: 2400)
      norm = described_class.new(ufo, target_upm: target_upm)
      expect(norm.scale_factor).to be_within(0.0001).of(0.416666666666667)
    end
  end

  describe "#identity?" do
    it "returns true when source UPM matches target" do
      ufo = build_ufo(units_per_em: 1000)
      expect(described_class.new(ufo, target_upm: 1000)).to be_identity
    end

    it "returns false when source UPM differs from target" do
      ufo = build_ufo(units_per_em: 2048)
      expect(described_class.new(ufo, target_upm: 1000)).not_to be_identity
    end
  end

  describe "#apply!" do
    it "sets fontinfo.units_per_em to target" do
      ufo = build_ufo(units_per_em: 2048)
      described_class.apply!(ufo, target_upm: 1000)
      expect(ufo.info.units_per_em).to eq(1000)
    end

    it "scales all glyph contour points by scale_factor" do
      ufo = build_ufo(units_per_em: 2048)
      glyph = add_glyph(ufo, "test", width: 2048)
      add_point(glyph, x: 1024, y: 512)

      described_class.apply!(ufo, target_upm: 1000)

      point = ufo.glyphs["test"].contours.first.points.first
      expect(point.x).to eq(500)
      expect(point.y).to eq(250)
    end

    it "scales advance width" do
      ufo = build_ufo(units_per_em: 2048)
      add_glyph(ufo, "test", width: 2048)

      described_class.apply!(ufo, target_upm: 1000)

      expect(ufo.glyphs["test"].width).to eq(1000)
    end

    it "scales open_type_hhea_ascender when present" do
      ufo = build_ufo(units_per_em: 2048)
      ufo.info.open_type_hhea_ascender = 1638

      described_class.apply!(ufo, target_upm: 1000)

      expect(ufo.info.open_type_hhea_ascender).to eq(800)
    end

    it "does not mutate the UFO when identity?" do
      ufo = build_ufo(units_per_em: 1000)
      glyph = add_glyph(ufo, "test", width: 500)
      add_point(glyph, x: 100, y: 200)
      original_x = ufo.glyphs["test"].contours.first.points.first.x

      described_class.apply!(ufo, target_upm: 1000)

      expect(ufo.glyphs["test"].contours.first.points.first.x).to eq(original_x)
    end

    it "preserves point type and smooth flag" do
      ufo = build_ufo(units_per_em: 2048)
      glyph = add_glyph(ufo, "test", width: 100)
      add_point(glyph, x: 1024, y: 0, type: "curve", smooth: true)

      described_class.apply!(ufo, target_upm: 1000)

      point = ufo.glyphs["test"].contours.first.points.first
      expect(point.type).to eq("curve")
      expect(point.smooth).to be true
    end
  end

  describe ".apply!" do
    it "returns the normalized UFO" do
      ufo = build_ufo(units_per_em: 2048)
      result = described_class.apply!(ufo, target_upm: 1000)
      expect(result).to equal(ufo)
    end
  end

  # -- Helpers -----------------------------------------------------------

  def build_ufo(units_per_em:)
    ufo = Fontisan::Ufo::Font.new
    ufo.info.units_per_em = units_per_em
    ufo
  end

  def add_glyph(ufo, name, width:)
    glyph = Fontisan::Ufo::Glyph.new(name: name)
    glyph.width = width
    ufo.layers.default_layer.add(glyph)
    glyph
  end

  def add_point(glyph, x:, y:, type: "line", smooth: false)
    point = Fontisan::Ufo::Point.new(x: x, y: y, type: type, smooth: smooth)
    contour = Fontisan::Ufo::Contour.new([point])
    glyph.add_contour(contour)
  end
end
