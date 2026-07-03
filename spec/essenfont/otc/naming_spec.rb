# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::Otc::Naming do
  it "exposes family, subfamily, copyright constants" do
    expect(described_class::FAMILY).to eq("essenfont")
    expect(described_class::SUBFAMILY).to eq("Regular")
    expect(described_class::COPYRIGHT).to match(/OFL 1.1/)
  end

  it "version_string reads from the VERSION file via Otc::Version" do
    expect(described_class.version_string).to eq(Essenfont::Otc::Version::STRING)
  end

  it "parses version into major/minor from the VERSION file" do
    major, minor = Essenfont::Otc::Version::STRING.split(".").map(&:to_i)
    expect(described_class.version_major).to eq(major)
    expect(described_class.version_minor).to eq(minor)
  end
end
