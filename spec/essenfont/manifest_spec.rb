# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Essenfont::Manifest do
  let(:manifest_yaml) do
    <<~YAML
      donors:
        - label: noto_sans
          family: Noto Sans
          file: NotoSans-Regular.ttf
          license: OFL-1.1
          sha256: abc123
          covers:
            - Basic_Latin
            - Latin_1_Supplement
          url: https://fonts.google.com/noto
        - label: disabled_donor
          family: Disabled
          file: disabled.ttf
          enabled: false
          covers:
            - Tolong_Siki
        - label: synthetic
          family: Synthetic
          type: code_chart
          block: Tolong-Siki
          covers:
            - Tolong_Siki
    YAML
  end

  let(:collection) do
    Tempfile.create(["manifest", ".yml"]) do |f|
      f.write(manifest_yaml)
      f.close
      described_class.load(path: f.path)
    end
  end

  it "loads all entries from YAML" do
    expect(collection.size).to eq(3)
  end

  describe "#active" do
    it "excludes entries with enabled: false" do
      labels = collection.active.map(&:label)
      expect(labels).to contain_exactly(:noto_sans, :synthetic)
    end
  end

  describe "#find" do
    it "looks up by symbol label" do
      expect(collection.find(:noto_sans).family).to eq("Noto Sans")
    end

    it "looks up by string label" do
      expect(collection.find("noto_sans").family).to eq("Noto Sans")
    end

    it "returns nil for unknown labels" do
      expect(collection.find(:nope)).to be_nil
    end
  end

  describe "#declared_blocks" do
    it "returns the unique union of covers: across all entries" do
      expect(collection.declared_blocks).to contain_exactly(
        "Basic_Latin", "Latin_1_Supplement", "Tolong_Siki"
      )
    end
  end

  describe "Entry" do
    it "exposes typed accessors" do
      e = collection.find(:noto_sans)
      expect(e.label).to eq(:noto_sans)
      expect(e.family).to eq("Noto Sans")
      expect(e.license).to eq("OFL-1.1")
      expect(e.covers).to eq(["Basic_Latin", "Latin_1_Supplement"])
      expect(e.enabled).to eq(true)
    end

    it "marks code_chart entries" do
      expect(collection.find(:synthetic).code_chart?).to be true
      expect(collection.find(:noto_sans).code_chart?).to be false
    end

    it "detects remap presence" do
      expect(collection.find(:noto_sans).remap?).to be false
    end
  end

  it "raises ManifestMissing on a nonexistent file" do
    expect { described_class.load(path: "/nope/manifest.yml") }
      .to raise_error(Essenfont::Otc::Errors::ManifestMissing, /manifest not found/)
  end
end
