# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Essenfont::Otc::Build, :integration do
  # Default to the repo's own references/input-fonts, computed relative
  # to the spec file so the path is portable. Override via ENV when
  # running elsewhere.
  let(:donor_dir) do
    ENV.fetch("ESSENFONT_DONOR_DIR",
              File.expand_path("../../../references/input-fonts", __dir__))
  end
  let(:multani_path) { File.join(donor_dir, "NotoSansMultani-Regular.ttf") }
  let(:adlam_path)   { File.join(donor_dir, "NotoSansAdlam-Regular.ttf") }

  let(:donors) do
    {
      noto_multani: Essenfont::Donor::Info.new(label: :noto_multani, font: Fontisan::FontLoader.load(multani_path)),
      noto_adlam:   Essenfont::Donor::Info.new(label: :noto_adlam,   font: Fontisan::FontLoader.load(adlam_path))
    }
  end

  let(:cp_map) do
    multani = donors[:noto_multani].font.table("cmap").unicode_mappings
    adlam = donors[:noto_adlam].font.table("cmap").unicode_mappings.reject { |cp, _| cp < 0x10000 }

    map = {}
    multani.each { |cp, gid| map[cp] = { label: :noto_multani, gid: gid } }
    adlam.each { |cp, gid| map[cp] = { label: :noto_adlam, gid: gid } }
    map
  end

  describe ".new — argument validation" do
    it "rejects non-Hash cp_map" do
      expect { described_class.new(cp_map: [], donors: {}) }
        .to raise_error(ArgumentError, /cp_map must be a Hash/)
    end

    it "rejects non-Hash donors" do
      expect { described_class.new(cp_map: {}, donors: []) }
        .to raise_error(ArgumentError, /donors must be a Hash/)
    end
  end

  describe "#call — end-to-end", :slow do
    before do
      skip "donor fonts missing" unless File.exist?(multani_path) && File.exist?(adlam_path)
    end

    it "partitions by plane, stitches, and writes the collection (default glyf/TTC)" do
      Dir.mktmpdir("build-spec-") do |dir|
        out_path = File.join(dir, "essenfont-test.ttc")
        result = described_class.new(cp_map: cp_map, donors: donors).call(output_path: out_path)

        expect(result).to be_a(Essenfont::Otc::Build::Result)
        expect(result.output_path).to eq(out_path)
        expect(result.bytes).to be > 0
        expect(result.subfont_count).to eq(2)
        expect(result.subfonts.map { |s| s[:name] }).to contain_exactly(:plane_0, :plane_1)

        reader = Fontisan::Collection::Reader.open(out_path)
        expect(reader.face_count).to eq(2)
        reader.stats.each { |s| expect(s.glyph_count).to be <= 65_535 }
      end
    end

    it "produces a smaller file with CFF2 outlines" do
      Dir.mktmpdir("cff2-spec-") do |dir|
        ttc_path = File.join(dir, "out.ttc")
        otc_path = File.join(dir, "out.otc")

        ttc_result = described_class.new(cp_map: cp_map, donors: donors,
                                         subfont_format: :ttf).call(output_path: ttc_path)
        otc_result = described_class.new(cp_map: cp_map, donors: donors,
                                         subfont_format: :otf2).call(output_path: otc_path)

        expect(otc_result.bytes).to be < ttc_result.bytes

        # CFF2 table present in the OTC
        face = Fontisan::FontLoader.load(otc_path, font_index: 0)
        expect(face.has_table?("CFF2")).to be true
      end
    end

    it "uses PartitionStrategy::ByPlane by default" do
      build = described_class.new(cp_map: cp_map, donors: donors)
      expect(build.partitioner).to be_a(Fontisan::Stitcher::PartitionStrategy::ByPlane)
    end

    it "accepts a custom partitioner" do
      custom = Fontisan::Stitcher::PartitionStrategy::ByPlane.new
      build = described_class.new(cp_map: cp_map, donors: donors, partitioner: custom)
      expect(build.partitioner).to be(custom)
    end
  end
end
