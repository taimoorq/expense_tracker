require "rails_helper"

RSpec.describe Platform::BackupRestorePreviewStore do
  it "stores encrypted preview payloads behind a one-way token digest" do
    user = create(:user)
    payload = {
      format: Platform::UserDataExport::FORMAT_NAME,
      version: 1,
      data: { preferences: { default_landing_page: "accounts" } }
    }

    token = described_class.new(user: user).store(
      payload: payload,
      scopes: [ "preferences" ],
      encrypted: false
    )
    draft = BackupRestoreDraft.sole

    expect(draft.token_digest).to eq(Digest::SHA256.hexdigest(token))
    expect(draft.encrypted_payload).not_to include("default_landing_page", "accounts")
    expect(described_class.new(user: user).load(token)).to include(
      payload: include(format: Platform::UserDataExport::FORMAT_NAME, version: 1),
      scopes: [ "preferences" ],
      encrypted: false
    )
  end
end
