require "rails_helper"

RSpec.describe Accounts::ActivityImports::PreviewStore do
  include ActiveSupport::Testing::TimeHelpers

  def preview(account)
    {
      ok: true,
      account_id: account.id,
      file_digest: Digest::SHA256.hexdigest("preview-file"),
      commit_idempotency_key: Digest::SHA256.hexdigest("preview-commit"),
      rows_count: 0,
      imported_count: 0,
      duplicate_count: 0,
      rows: [],
      warnings: []
    }
  end

  it "persists a short-lived preview with a one-way token digest" do
    user = create(:user)
    account = create(:account, user: user, budget_workspace: nil, currency_code: nil)
    store = described_class.new(user: user)

    token = store.store(preview(account))
    draft = AccountActivityImportDraft.sole

    expect(draft.token_digest).to eq(Digest::SHA256.hexdigest(token))
    expect(draft.token_digest).not_to eq(token)
    expect(draft).to have_attributes(user: user, account: account)
    expect(account.reload.budget_workspace).to eq(draft.budget_workspace)
    expect(store.load(token)).to include(account_id: account.id, ok: true)
  end

  it "does not expose expired or cross-user previews" do
    user = create(:user)
    account = create(:account, user: user)
    token = described_class.new(user: user, expires_in: 1.second).store(preview(account))

    travel 2.seconds do
      expect(described_class.new(user: user).load(token)).to be_nil
      expect(described_class.new(user: create(:user)).load(token)).to be_nil
    end
  end
end
