require "rails_helper"

RSpec.describe Platform::Backup::ArchiveConfiguration do
  it "is dormant without explicit host configuration" do
    configuration = described_class.new(environment: {})

    expect(configuration).not_to be_ready
    expect(configuration.safe_label).to eq("Not configured")
  end

  it "accepts an absolute local root and a 32-byte base64 key" do
    configuration = described_class.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "local",
        "BACKUP_LOCAL_ROOT" => "/srv/finance-tracking/backups",
        "BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32),
        "BACKUP_ENCRYPTION_KEY_ID" => "2026-08"
      }
    )

    expect(configuration).to be_ready
    expect(configuration.primary_key_id).to eq("2026-08")
    expect(configuration.primary_key).to eq("k" * 32)
  end

  it "rejects relative paths and malformed keys" do
    configuration = described_class.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "local",
        "BACKUP_LOCAL_ROOT" => "backups",
        "BACKUP_ENCRYPTION_KEY" => "not-base64"
      }
    )

    expect(configuration).not_to be_ready
    expect(configuration.error).to eq("The local backup path must be absolute.")
  end

  it "requires a nonblank key ID" do
    configuration = described_class.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "local",
        "BACKUP_LOCAL_ROOT" => "/backups",
        "BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32),
        "BACKUP_ENCRYPTION_KEY_ID" => ""
      }
    )

    expect(configuration).not_to be_ready
    expect(configuration.error).to eq("A backup encryption key ID is required.")
  end

  it "accepts an S3 bucket, prefix, and region" do
    configuration = described_class.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "s3",
        "BACKUP_S3_BUCKET" => "finance-tracking-backups",
        "BACKUP_S3_PREFIX" => "/local/archives/",
        "BACKUP_S3_REGION" => "us-east-1",
        "BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)
      }
    )

    expect(configuration).to be_ready
    expect(configuration.s3_prefix).to eq("local/archives")
    expect(configuration.safe_label).to eq("S3-compatible object storage")
  end

  it "rejects incomplete S3 configuration" do
    configuration = described_class.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "s3",
        "BACKUP_S3_REGION" => "us-east-1",
        "BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)
      }
    )

    expect(configuration).not_to be_ready
    expect(configuration.error).to eq("An S3 backup bucket is required.")
  end
end
