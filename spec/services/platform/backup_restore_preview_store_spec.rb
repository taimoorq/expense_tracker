require "rails_helper"

RSpec.describe Platform::BackupRestorePreviewStore do
  it "stores preview tokens in the configured Rails cache" do
    user = create(:user)
    configured_store = ActiveSupport::Cache::MemoryStore.new

    allow(Rails).to receive(:cache).and_return(configured_store)

    token = described_class.new(user: user).store(
      payload: { format: "expense_tracker_backup" },
      scopes: [ "accounts" ],
      encrypted: false
    )

    expect(configured_store.exist?("backup_restore_preview:#{user.id}:#{token}")).to be(true)
    expect(described_class.new(user: user).load(token)).to include(
      payload: { format: "expense_tracker_backup" },
      scopes: [ "accounts" ],
      encrypted: false
    )
  end
end
