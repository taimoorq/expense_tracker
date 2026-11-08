require "rails_helper"

RSpec.describe Platform::UserDataBackupCodec do
  let(:payload) { { format: Platform::UserDataExport::FORMAT_NAME, version: 1, data: { preferences: { financial_rhythm: "monthly" } } } }

  it "rejects excessive wire bytes before JSON parsing and rewinds uploads" do
    stub_const("Platform::ImportLimits::BACKUP_MAX_WIRE_BYTES", 32)
    input = StringIO.new("x" * 33)
    expect(JSON).not_to receive(:parse)

    expect(described_class.decode(source: input)).to include(success: false, error: include("size limit"))
    expect(input.pos).to eq(0)
  end

  it "bounds decrypted contents before parsing them" do
    encoded = described_class.encode(payload: payload, password: "a-test-password")
    stub_const("Platform::ImportLimits::BACKUP_MAX_BYTES", 32)

    expect(described_class.decode(source: encoded, password: "a-test-password"))
      .to include(success: false, error: include("Backup contents", "size limit"))
  end

  it "keeps plain and password-protected legacy backups readable" do
    [ nil, "a-test-password" ].each do |password|
      encoded = described_class.encode(payload: payload, password: password)
      expect(described_class.decode(source: encoded, password: password))
        .to include(success: true, payload: payload, encrypted: password.present?)
    end
  end

  it "round-trips near-limit backups without export whitespace exceeding the restore budget" do
    limit = Platform::CanonicalJson.dump(payload).bytesize
    stub_const("Platform::ImportLimits::BACKUP_MAX_BYTES", limit)
    expect(JSON.pretty_generate(payload).bytesize).to be > limit

    [ nil, "a-test-password" ].each do |password|
      encoded = described_class.encode(payload: payload, password: password)

      expect(described_class.decode(source: encoded, password: password))
        .to include(success: true, payload: payload)
    end
  end

  it "rejects JSON scalars as unsupported backups" do
    expect(described_class.decode(source: "null")).to include(success: false)
  end
end
