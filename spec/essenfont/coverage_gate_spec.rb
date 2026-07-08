# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::CoverageGate do
  # CoverageGate works against the Manifest + donors-hash shapes used
  # in production. Using the real Manifest (from_hash) keeps the spec
  # honest about the data shape; Structs stand in for the donor half
  # because real donor fonts would force an integration test.
  let(:manifest) do
    Essenfont::Manifest.from_hash(
      "donors" => [
        { "label" => "real_donor", "covers" => ["Basic_Latin"] },
        { "label" => "lying_donor", "covers" => ["Phags-pa"] },
        { "label" => "remapped_donor", "covers" => ["Coptic"],
          "remap" => "sources/remaps/coptic.yml" },
        { "label" => "unloaded_donor", "covers" => ["Tibetan"] }
      ]
    )
  end

  # A donor's coverage is the hash of codepoints its cmap actually
  # contributes (cp → gid). Empty Hash simulates "loaded but cmap
  # doesn't cover the declared block"; populated Hash simulates real
  # coverage. Matches the shape DonorLoader returns in production.
  let(:donors) do
    {
      real_donor: {
        label: :real_donor,
        coverage: (0x41..0x7A).to_h { |cp| [cp, 1] }, # ASCII covers Basic Latin
        remap: nil
      },
      lying_donor: {
        label: :lying_donor,
        coverage: {}, # claims Phags_Pa but cmap has 0 cps there
        remap: nil
      },
      remapped_donor: {
        label: :remapped_donor,
        coverage: {},
        remap: { 0x41 => 0x1000 } # raw cmap ≠ target; gate must skip
      }
      # unloaded_donor intentionally absent from this hash
    }
  end

  let(:gate) { described_class.new(manifest:, donors:) }

  describe "#failures" do
    it "includes donors that declare a block but have 0 cmap coverage" do
      labels = gate.failures.map(&:label)
      expect(labels).to include(:lying_donor)
    end

    it "does not flag donors with real coverage" do
      labels = gate.failures.map(&:label)
      expect(labels).not_to include(:real_donor)
    end

    it "skips remapped donors (raw cmap is intentionally at non-target cps)" do
      labels = gate.failures.map(&:label)
      expect(labels).not_to include(:remapped_donor)
    end

    it "skips donors that weren't loaded (e.g. path_local_only)" do
      labels = gate.failures.map(&:label)
      expect(labels).not_to include(:unloaded_donor)
    end

    it "returns Failure records with label, block, and range" do
      failure = gate.failures.find { |f| f.label == :lying_donor }
      expect(failure.block).to eq("Phags-pa")
      expect(failure.range).to eq(Essenfont::UcodeRef.block_range("Phags-pa"))
    end

    it "produces a readable message" do
      failure = gate.failures.find { |f| f.label == :lying_donor }
      expect(failure.message).to match(/lying_donor: declares covers:Phags-pa/)
      expect(failure.message).to match(/U\+[0-9A-F]+\.\.U\+[0-9A-F]+/)
    end
  end

  describe "#validate!" do
    it "raises CoverageGateFailed when any failure exists" do
      expect { gate.validate! }.to raise_error(
        Essenfont::Otc::Errors::CoverageGateFailed, /lying_donor/
      )
    end

    context "with no failures" do
      let(:manifest) do
        Essenfont::Manifest.from_hash(
          "donors" => [
            { "label" => "real_donor", "covers" => ["Basic_Latin"] }
          ]
        )
      end

      let(:donors) do
        { real_donor: { label: :real_donor, coverage: (0x41..0x7A).to_h { |cp| [cp, 1] }, remap: nil } }
      end

      it "returns true without raising" do
        expect(gate.validate!).to be true
      end
    end
  end
end
