require "rails_helper"

RSpec.describe AccountActivityImportDraft do
  it "exposes only durable operation identity and clears financial rows when consumed" do
    draft = create(:account_activity_import_draft)

    expect(draft.operation_request).to include(
      account_id: draft.account_id,
      rows_count: 0
    )
    expect(draft.operation_request).not_to have_key(:draft_id)
    expect(draft.redacted_operation_parameters).not_to have_key(:file_digest)

    draft.consume!

    expect(draft).to be_state_consumed
    expect(draft.preview_payload).to eq({})
    expect(draft.consumed_at).to be_present
  end

  it "requires account, user, and workspace ownership to agree" do
    draft = build(:account_activity_import_draft)
    draft.user = create(:user)

    expect(draft).not_to be_valid
    expect(draft.errors[:account]).to include("must belong to the same user")
  end

  it "redacts staged financial payloads and opaque tokens from inspection" do
    draft = build(
      :account_activity_import_draft,
      preview_payload: { "description" => "PRIVATE MERCHANT" }
    )

    expect(draft.inspect).not_to include("PRIVATE MERCHANT", draft.token_digest)
    expect(draft.inspect).to include("[FILTERED]")
  end
end
