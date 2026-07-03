# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::Otc::Naming do
  it "exposes family, version, subfamily, copyright constants" do
    expect(described_class::FAMILY).to eq("essenfont")
    expect(described_class::VERSION).to eq("0.1")
    expect(described_class::SUBFAMILY).to eq("Regular")
    expect(described_class::COPYRIGHT).to match(/OFL 1.1/)
  end

  it "parses version into major/minor" do
    expect(described_class.version_major).to eq(0)
    expect(described_class.version_minor).to eq(1)
  end
end
