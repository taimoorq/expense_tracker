require "rails_helper"

RSpec.describe BackupRestoreDraft do
  it "redacts encrypted payloads and tokens from inspection" do
    draft = described_class.new(
      token_digest: "a" * 64,
      encrypted_payload: "PRIVATE BACKUP CIPHERTEXT"
    )

    expect(draft.inspect).not_to include("PRIVATE BACKUP CIPHERTEXT", "a" * 64)
    expect(draft.inspect).to include("[FILTERED]")
  end
end
