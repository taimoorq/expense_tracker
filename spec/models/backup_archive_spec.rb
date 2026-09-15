require "rails_helper"

RSpec.describe BackupArchive do
  it "requires scheduled archives to have a schedule and slot" do
    archive = build(:backup_archive, trigger: "scheduled")

    expect(archive).not_to be_valid
    expect(archive.errors[:scheduled_for]).to include("must match the archive trigger")
  end

  it "requires ready archives to have verified stored metadata" do
    archive = build(:backup_archive, state: "ready")

    expect(archive).not_to be_valid
    expect(archive.errors[:verified_at]).to include("is required for this state")
  end
end
