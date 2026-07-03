# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::Otc::Errors::Base do
  it "carries structured context (codepoint, donor, block)" do
    err = described_class.new("custom message",
                              codepoint: 0x1F600,
                              donor: :noto_emoji,
                              block: "Emoticons")
    expect(err.message).to include("custom message")
    expect(err.message).to include("U+1F600")
    expect(err.message).to include("noto_emoji")
    expect(err.message).to include("Emoticons")
    expect(err.codepoint).to eq(0x1F600)
    expect(err.donor).to eq(:noto_emoji)
    expect(err.block).to eq("Emoticons")
  end

  it "works without context" do
    err = described_class.new("bare")
    expect(err.message).to eq("bare")
    expect(err.codepoint).to be_nil
  end

  it "formats integer codepoints as U+HEX" do
    err = described_class.new("m", codepoint: 0x13000)
    expect(err.message).to include("U+13000")
  end
end

RSpec.describe Essenfont::Otc::Errors do
  it "all error subclasses inherit from Base" do
    %i[BuildError UnsupportedFormat DonorMissing DonorShaMismatch
       DonorFileInvalid CoverageGateFailed CollectionValidation
       ManifestMissing].each do |klass|
      expect(described_class.const_get(klass)).to be < described_class::Base
    end
  end
end

