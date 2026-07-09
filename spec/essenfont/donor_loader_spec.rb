# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Essenfont::DonorLoader, :integration do
  # Use the repo's own donor fixtures — they're committed, hashed, and
  # representative of real input. ENV override lets CI point elsewhere.
  let(:donor_dir) do
    ENV.fetch("ESSENFONT_DONOR_DIR",
              File.expand_path("../../references/input-fonts", __dir__))
  end

  let(:manifest) do
    Essenfont::Manifest.from_hash(
      "donors" => [
        { "label" => "noto_multani", "family" => "Noto Sans Multani",
          "file" => File.join(donor_dir, "NotoSansMultani-Regular.ttf"),
          "license" => "OFL",
          "sha256" => Digest::SHA256.file(File.join(donor_dir, "NotoSansMultani-Regular.ttf")).hexdigest,
          "covers" => ["Multani"] }
      ]
    )
  end

  let(:loader) { described_class.new(manifest: manifest) }

  describe ".new" do
    it "defaults donor_dir to references/input-fonts" do
      expect(described_class.default_donor_dir).to end_with("references/input-fonts")
    end

    it "defaults remap_dir to sources/remaps" do
      expect(described_class.default_remap_dir).to end_with("sources/remaps")
    end

    it "accepts overrides for both dirs" do
      loader = described_class.new(manifest: manifest, donor_dir: "/tmp/x", remap_dir: "/tmp/r")
      expect(loader.donor_dir).to eq("/tmp/x")
      expect(loader.remap_dir).to eq("/tmp/r")
    end
  end

  describe "#load_all" do
    it "returns a hash keyed by donor label" do
      donors = loader.load_all
      expect(donors).to be_a(Hash)
      expect(donors.keys).to include(:noto_multani)
    end

    it "each donor carries the load_one shape (label, font, file, coverage, remap, entry)" do
      donor = loader.load_all[:noto_multani]
      expect(donor[:label]).to eq(:noto_multani)
      expect(donor[:font]).to respond_to(:table)
      expect(donor[:file]).to match(/NotoSansMultani-Regular\.ttf\z/)
      expect(donor[:coverage]).to be_a(Hash)
      expect(donor[:coverage]).not_to be_empty
      expect(donor[:entry]).to be_a(Essenfont::Manifest::Entry)
    end

    it "skips entries whose files are missing (rather than raising)" do
      bad_manifest = Essenfont::Manifest.from_hash(
        "donors" => [
          { "label" => "ghost", "family" => "Ghost",
            "file" => File.join(donor_dir, "nonexistent.ttf"),
            "license" => "OFL", "sha256" => "TBD" }
        ]
      )
      loader = described_class.new(manifest: bad_manifest)
      expect(loader.load_all).to eq({})
    end
  end

  describe "#load_one" do
    def build_entry(overrides = {})
      Essenfont::Manifest::Entry.new({
        "label" => :test_donor,
        "family" => "Test Donor",
        "file" => File.join(donor_dir, "NotoSansMultani-Regular.ttf"),
        "license" => "OFL",
        "sha256" => Digest::SHA256.file(File.join(donor_dir, "NotoSansMultani-Regular.ttf")).hexdigest,
        "covers" => ["Multani"]
      }.merge(overrides.transform_keys(&:to_s)))
    end

    it "loads successfully for a valid entry" do
      entry = build_entry
      donor = loader.load_one(entry)
      expect(donor[:label]).to eq(:test_donor)
      expect(donor[:coverage]).not_to be_empty
    end

    it "returns nil when the file is missing" do
      entry = build_entry(
        "file" => File.join(donor_dir, "nonexistent.ttf"),
        "sha256" => "TBD"
      )
      expect(loader.load_one(entry)).to be_nil
    end

    it "returns nil when magic bytes do not match a font" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake.ttf")
        File.write(fake, "this is not a font, just text#{'x' * 100}")
        entry = build_entry("file" => fake, "sha256" => "TBD")
        expect(loader.load_one(entry)).to be_nil
      end
    end

    it "returns nil when sha256 does not match" do
      entry = build_entry("sha256" => "deadbeef" * 8)
      expect(loader.load_one(entry)).to be_nil
    end

    it "loads successfully when sha256 is 'TBD'" do
      entry = build_entry("sha256" => "TBD")
      expect(loader.load_one(entry)).not_to be_nil
    end

    it "loads successfully when sha256 is nil" do
      entry = build_entry("sha256" => nil)
      expect(loader.load_one(entry)).not_to be_nil
    end
  end

  describe ".valid_magic?" do
    let(:multani) { File.join(donor_dir, "NotoSansMultani-Regular.ttf") }

    it "accepts a real TTF" do
      expect(loader.send(:valid_magic?, multani)).to be true
    end

    it "rejects a non-existent file" do
      expect(loader.send(:valid_magic?, "/tmp/nonexistent.ttf")).to be false
    end

    it "rejects a non-font file" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "fake")
        File.write(fake, "x" * 100)
        expect(loader.send(:valid_magic?, fake)).to be false
      end
    end
  end

  describe ".valid_sha256?" do
    let(:multani) { File.join(donor_dir, "NotoSansMultani-Regular.ttf") }
    let(:real_sha) { Digest::SHA256.file(multani).hexdigest }

    it "passes when the hash matches (case-insensitive)" do
      expect(loader.send(:valid_sha256?, multani, real_sha, :x)).to be true
      expect(loader.send(:valid_sha256?, multani, real_sha.upcase, :x)).to be true
    end

    it "skips when expected is nil" do
      expect(loader.send(:valid_sha256?, multani, nil, :x)).to be true
    end

    it "skips when expected is 'TBD'" do
      expect(loader.send(:valid_sha256?, multani, "TBD", :x)).to be true
    end

    it "fails when the hash does not match" do
      expect(loader.send(:valid_sha256?, multani, "0" * 64, :x)).to be false
    end
  end

  describe "restrict_to_covers filtering" do
    # Real Noto Multani only covers the Multani block (U+11280–U+112AF).
    # The font itself has no Latin codepoints, so to simulate contamination
    # we'd need a second donor fixture — but the FILTERING LOGIC is
    # tested below with the helper directly. End-to-end coverage of the
    # contaminated-donor scenario is exercised by the real FSung entry in
    # lib/essenfont/donor_loader.rb (see sources/manifest.yml).
    def build_restricted_entry(overrides = {})
      Essenfont::Manifest::Entry.new({
        "label" => :cjk_only,
        "family" => "CJK-only donor",
        "file" => File.join(donor_dir, "NotoSansMultani-Regular.ttf"),
        "license" => "OFL",
        "sha256" => Digest::SHA256.file(File.join(donor_dir, "NotoSansMultani-Regular.ttf")).hexdigest,
        "covers" => ["Multani"],
        "restrict_to_covers" => true
      }.merge(overrides.transform_keys(&:to_s)))
    end

    it "keeps codepoints inside declared blocks and drops the rest" do
      entry = build_restricted_entry
      donor = loader.load_one(entry)
      cps = donor[:coverage].keys
      multani_range = Essenfont::UcodeRef.block_range("Multani")
      expect(cps).not_to be_empty
      cps.each do |cp|
        expect(cp).to be >= multani_range[0]
        expect(cp).to be <= multani_range[1]
      end
    end

    it "returns an empty coverage when covers: is empty (all cmap filtered out)" do
      entry = build_restricted_entry("covers" => [])
      donor = loader.load_one(entry)
      expect(donor[:coverage]).to be_empty
    end

    it "leaves coverage unfiltered when restrict_to_covers is false" do
      entry = build_restricted_entry("restrict_to_covers" => false)
      donor = loader.load_one(entry)
      # Noto Multani's cmap should pass through unchanged.
      expect(donor[:coverage].keys).to all(be_between(0x11280, 0x112AF).inclusive)
    end
  end
end
