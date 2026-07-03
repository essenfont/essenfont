# frozen_string_literal: true

require "spec_helper"

RSpec.describe Essenfont::Otc do
  it "exposes a VERSION constant" do
    expect(described_class::Version::STRING).to eq("0.1.0")
  end

  it "autoloads Build, Naming, Errors" do
    expect(described_class::Build).to be_a(Class)
    expect(described_class::Naming).to be_a(Module)
    expect(described_class::Errors::Base).to be < StandardError
  end

  it "does NOT autoload classes now provided by fontisan" do
    # These were moved to fontisan/ucode — essenfont must not redefine them.
    expect(described_class).not_to be_const_defined(:Plane)
    expect(described_class).not_to be_const_defined(:Partition)
    expect(described_class).not_to be_const_defined(:Blueprint)
    expect(described_class).not_to be_const_defined(:PlanePartitioner)
    expect(described_class).not_to be_const_defined(:Writer)
    expect(described_class).not_to be_const_defined(:StitcherSession)
  end
end
