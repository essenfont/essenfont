# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Essenfont::Otc::Validator, :integration do
  let(:donor_dir) do
    ENV.fetch("ESSENFONT_DONOR_DIR",
              File.expand_path("../../../references/input-fonts", __dir__))
  end
  let(:valid_font) { File.join(donor_dir, "NotoSansMultani-Regular.ttf") }

  describe ".check" do
    it "returns empty failures for a valid font" do
      skip "donor font missing" unless File.exist?(valid_font)

      failures = described_class.check(valid_font)
      expect(failures).to be_empty
    end

    it "returns a file-not-found failure for a missing path" do
      failures = described_class.check("/nonexistent/font.ttf")
      expect(failures.size).to eq(1)
      expect(failures.first.message).to match(/file not found/)
    end

    it "returns a failure for a non-font file" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake.ttf")
        File.write(fake, "not a font" + "x" * 100)

        failures = described_class.check(fake)
        expect(failures).not_to be_empty
      end
    end
  end

  describe ".check!" do
    it "does not raise for a valid font" do
      skip "donor font missing" unless File.exist?(valid_font)

      expect { described_class.check!(valid_font) }.not_to raise_error
    end

    it "raises CollectionValidation for a missing file" do
      expect { described_class.check!("/nonexistent/font.ttf") }
        .to raise_error(Essenfont::Otc::Errors::CollectionValidation, /file not found/)
    end
  end

  describe "Failure" do
    it "formats message with detail" do
      failure = Essenfont::Otc::Validator::Failure.new(
        description: "glyph cap", detail: "face 0 has 70000 glyphs"
      )
      expect(failure.message).to eq("glyph cap (face 0 has 70000 glyphs)")
    end

    it "formats message without detail" do
      failure = Essenfont::Otc::Validator::Failure.new(description: "cmap missing")
      expect(failure.message).to eq("cmap missing")
    end
  end
end
