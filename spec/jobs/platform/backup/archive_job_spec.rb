require "rails_helper"
require "active_job/continuation/test_helper"
require "tmpdir"

RSpec.describe Platform::Backup::ArchiveJob, type: :job do
  include ActiveJob::Continuation::TestHelper
  include ActiveJob::TestHelper

  around do |example|
    Dir.mktmpdir("finance-tracking-backups") do |directory|
      original_environment = ENV.to_h.slice(
        "BACKUP_STORAGE_DRIVER",
        "BACKUP_LOCAL_ROOT",
        "BACKUP_ENCRYPTION_KEY",
        "BACKUP_ENCRYPTION_KEY_ID",
        "BACKUP_ENCRYPTION_PREVIOUS_KEYS"
      )
      ENV["BACKUP_STORAGE_DRIVER"] = "local"
      ENV["BACKUP_LOCAL_ROOT"] = directory
      ENV["BACKUP_ENCRYPTION_KEY"] = Base64.strict_encode64("k" * 32)
      ENV.delete("BACKUP_ENCRYPTION_KEY_ID")
      ENV.delete("BACKUP_ENCRYPTION_PREVIOUS_KEYS")
      @configuration = Platform::Backup::ArchiveConfiguration.new(
        environment: ENV
      )
      example.run
    ensure
      %w[
        BACKUP_STORAGE_DRIVER BACKUP_LOCAL_ROOT BACKUP_ENCRYPTION_KEY
        BACKUP_ENCRYPTION_KEY_ID BACKUP_ENCRYPTION_PREVIOUS_KEYS
      ].each { |key| ENV.delete(key) }
      original_environment.each { |key, value| ENV[key] = value }
    end
  end

  def dispatch
    user = create(:user)
    create(:account, user: user, name: "Private checking")
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    result = Platform::Backup::ArchiveDispatch.call(user: user, configuration: @configuration)
    clear_enqueued_jobs
    result
  end

  def legacy_dispatch
    user = create(:user)
    create(:account, user: user, name: "Legacy private checking")
    Platform::TargetBackfill::WorkspaceBootstrap.call(user: user)
    result = Platform::Backup::ArchiveDispatch.call(user: user, configuration: @configuration)
    clear_enqueued_jobs
    result
  end

  it "stores, verifies, and records a restorable encrypted archive" do
    result = dispatch

    described_class.perform_now(result.operation.id, result.archive.id)

    archive = result.archive.reload
    expect(archive).to be_state_ready
    expect(archive).to have_attributes(byte_size: be_positive, archive_checksum: match(/\A[0-9a-f]{64}\z/))
    expect(result.operation.reload).to have_attributes(state: "succeeded", progress_current: 4, progress_total: 4)
    contents = Platform::Backup::Storage.build(@configuration).read(archive.storage_key)
    expect(contents).not_to include("Private checking")
    expect(Platform::UserDataBackupCodec.decode(source: contents, archive_configuration: @configuration)).to include(success: true)
    expect(archive.data_transfer_run.reload).to be_state_succeeded
    expect(archive.budget_workspace.audit_events.where(action: "backup_export")).to exist
  end

  it "reconciles a stored effect after a crash before database completion" do
    result = dispatch
    archive = result.archive
    exporter = Platform::Backup::V2::Exporter.new(
      user: archive.actor_membership.user,
      scopes: archive.data_transfer_run.selected_scopes
    )
    payload = exporter.as_json
    contents = Platform::Backup::ArchiveCodec.encode(payload: payload, configuration: @configuration)
    archive.begin_writing!(
      payload_checksum: payload.fetch(:payload_checksum),
      archive_checksum: Digest::SHA256.hexdigest(contents),
      byte_size: contents.bytesize
    )
    Platform::Backup::Storage.build(@configuration).write(
      key: archive.storage_key,
      contents: contents,
      checksum: archive.archive_checksum
    )

    described_class.perform_now(result.operation.id, archive.id)

    expect(archive.reload).to be_state_ready
    expect(result.operation.reload).to be_state_succeeded
  end

  it "stores and verifies a checksummed legacy archive before target cutover" do
    result = legacy_dispatch

    described_class.perform_now(result.operation.id, result.archive.id)

    archive = result.archive.reload
    contents = Platform::Backup::Storage.build(@configuration).read(archive.storage_key)
    decoded = Platform::UserDataBackupCodec.decode(source: contents, archive_configuration: @configuration)
    expect(archive).to be_state_ready
    expect(archive.payload_format_version).to eq("1")
    expect(decoded).to include(success: true)
    expect(decoded.fetch(:payload)).to include(version: 1, payload_checksum: match(/\A[0-9a-f]{64}\z/))
  end
end
