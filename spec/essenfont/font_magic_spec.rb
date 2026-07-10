# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Essenfont::FontMagic do
  let(:donor_dir) do
    ENV.fetch("ESSENFONT_DONOR_DIR",
              File.expand_path("../../references/input-fonts", __dir__))
  end

  describe ".valid?" do
    it "accepts a real TTF" do
      multani = File.join(donor_dir, "NotoSansMultani-Regular.ttf")
      skip "donor font missing" unless File.exist?(multani)
      expect(described_class.valid?(multani)).to be true
    end

    it "rejects a non-existent file" do
      expect(described_class.valid?("/tmp/nonexistent.ttf")).to be false
    end

    it "rejects a non-font file" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake")
        File.write(fake, "x" * 100)
        expect(described_class.valid?(fake)).to be false
      end
    end

    it "accepts an OTF (CFF magic)" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake.otf")
        File.binwrite(fake, "OTTO" + "\x00" * 20)
        expect(described_class.valid?(fake)).to be true
      end
    end

    it "accepts a TTC" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake.ttc")
        File.binwrite(fake, "ttcf" + "\x00" * 20)
        expect(described_class.valid?(fake)).to be true
      end
    end

    it "accepts a WOFF" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake.woff")
        File.binwrite(fake, "wOFF" + "\x00" * 20)
        expect(described_class.valid?(fake)).to be true
      end
    end

    it "accepts a WOFF2" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake.woff2")
        File.binwrite(fake, "wOF2" + "\x00" * 20)
        expect(described_class.valid?(fake)).to be true
      end
    end
  end
end
