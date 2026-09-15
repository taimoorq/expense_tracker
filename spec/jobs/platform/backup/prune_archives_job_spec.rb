require "rails_helper"
require "tmpdir"

RSpec.describe Platform::Backup::PruneArchivesJob, type: :job do
  around do |example|
    Dir.mktmpdir("finance-tracking-backups") do |directory|
      original = ENV.to_h.slice("BACKUP_STORAGE_DRIVER", "BACKUP_LOCAL_ROOT", "BACKUP_ENCRYPTION_KEY")
      ENV["BACKUP_STORAGE_DRIVER"] = "local"
      ENV["BACKUP_LOCAL_ROOT"] = directory
      ENV["BACKUP_ENCRYPTION_KEY"] = Base64.strict_encode64("k" * 32)
      @configuration = Platform::Backup::ArchiveConfiguration.current
      example.run
    ensure
      %w[BACKUP_STORAGE_DRIVER BACKUP_LOCAL_ROOT BACKUP_ENCRYPTION_KEY].each { |key| ENV.delete(key) }
      original.each { |key, value| ENV[key] = value }
    end
  end

  it "deletes only archives beyond retention and preserves the newest verified set" do
    schedule = create(:backup_schedule, retention_count: 7)
    storage = Platform::Backup::Storage.build(@configuration)
    archives = 8.times.map do |index|
      contents = "archive-#{index}"
      archive = create(
        :backup_archive,
        :ready,
        budget_workspace: schedule.budget_workspace,
        actor_membership: schedule.creator_membership,
        storage_key: "workspaces/#{schedule.budget_workspace_id}/archive-#{index}.json",
        archive_checksum: Digest::SHA256.hexdigest(contents),
        byte_size: contents.bytesize,
        stored_at: index.hours.ago,
        verified_at: index.hours.ago
      )
      storage.write(key: archive.storage_key, contents: contents, checksum: archive.archive_checksum)
      archive
    end

    described_class.perform_now(schedule.budget_workspace_id)

    expect(schedule.budget_workspace.backup_archives.state_ready.count).to eq(7)
    deleted = schedule.budget_workspace.backup_archives.state_deleted.sole
    expect(deleted).to eq(archives.last)
    expect(storage.stat(deleted.storage_key)).to be_nil
  end
end
