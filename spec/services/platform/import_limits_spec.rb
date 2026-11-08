require "rails_helper"

RSpec.describe Platform::ImportLimits do
  it "bounds reads even when the input has no size metadata" do
    input = StringIO.new("x" * 65)
    expect { described_class.read(input, max_bytes: 64, label: "Upload") }
      .to raise_error(described_class::Exceeded, /size limit/)
    expect(input.pos).to eq(65)
  end

  it "accepts the exact byte boundary for strings and streams" do
    expect(described_class.read("é" * 4, max_bytes: 8, label: "Upload")).to eq("é" * 4)
    expect(described_class.read(StringIO.new("x" * 8), max_bytes: 8, label: "Upload")).to eq("x" * 8)
  end
end
