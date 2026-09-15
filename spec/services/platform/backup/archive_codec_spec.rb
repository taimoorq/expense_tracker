require "rails_helper"

RSpec.describe Platform::Backup::ArchiveCodec do
  def configuration(primary: "a" * 32, key_id: "current", previous: {})
    Platform::Backup::ArchiveConfiguration.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "local",
        "BACKUP_LOCAL_ROOT" => "/tmp/finance-tracking-backups",
        "BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64(primary),
        "BACKUP_ENCRYPTION_KEY_ID" => key_id,
        "BACKUP_ENCRYPTION_PREVIOUS_KEYS" => JSON.generate(
          previous.transform_values { |key| Base64.strict_encode64(key) }
        )
      }
    )
  end

  let(:payload) do
    {
      format: Platform::UserDataExport::FORMAT_NAME,
      version: 2,
      payload_checksum: "a" * 64,
      data: {}
    }
  end

  it "round trips an installation-key encrypted payload" do
    config = configuration
    encoded = described_class.encode(payload: payload, configuration: config)
    decoded = Platform::UserDataBackupCodec.decode(source: encoded, archive_configuration: config)

    expect(encoded).not_to include(payload.to_json)
    expect(decoded).to include(success: true, encrypted: true, protection: "installation_key", key_id: "current")
    expect(decoded.fetch(:payload)).to eq(payload)
  end

  it "decrypts retained archives with a previous key" do
    old_config = configuration(primary: "o" * 32, key_id: "old")
    encoded = described_class.encode(payload: payload, configuration: old_config)
    rotated = configuration(primary: "n" * 32, key_id: "new", previous: { "old" => "o" * 32 })

    expect(Platform::UserDataBackupCodec.decode(source: encoded, archive_configuration: rotated)).to include(success: true)
  end

  it "fails clearly when the required key is absent" do
    old_config = configuration(primary: "o" * 32, key_id: "old")
    encoded = described_class.encode(payload: payload, configuration: old_config)

    result = Platform::UserDataBackupCodec.decode(source: encoded, archive_configuration: configuration)

    expect(result).to eq(success: false, error: "The encryption key required for this automatic backup is not configured.")
  end
end
