require "rails_helper"

RSpec.describe Platform::CanonicalJson do
  it "keeps canonical bytes for nested keys, collisions, and financial types" do
    payload = {
      z: [ { b: BigDecimal("12.340"), a: :posted, "b" => BigDecimal("56.780") } ],
      "a" => { occurred_on: Date.new(2026, 11, 7), at: Time.utc(2026, 11, 7, 12) },
      3 => nil
    }

    expect(described_class.dump(payload)).to eq(
      '{"3":null,"a":{"at":"2026-11-07T12:00:00Z","occurred_on":"2026-11-07"},"z":[{"a":"posted","b":"56.78"}]}'
    )
    expect(payload[:z].first[:b]).to eq(BigDecimal("12.340"))
  end
end
