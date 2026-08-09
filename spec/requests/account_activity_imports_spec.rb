require "rails_helper"

RSpec.describe "Account activity imports", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:account) { create(:account, user: user, name: "Rewards Card", kind: :credit_card) }

  before { sign_in user }

  it "describes the account activity import stages and pending preview state" do
    get new_account_account_activity_import_path(account)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import stages")
    expect(response.body).to include('aria-label="Breadcrumb"')
    expect(response.body).to include("Rewards Card")
    expect(response.body).to include("Import Account Activity")
    expect(response.body).to include("What has already been imported")
    expect(response.body).to include("No account files imported yet")
    expect(response.body).to include("Building preview...")
    expect(response.body).to include("Preview submitted")
    expect(response.body).to include("imported account balances become the trusted balance source over snapshots")
    expect(response.body).to include('data-controller="file-drop turbo-submit"')
    expect(response.body).to include('data-turbo="false"')
  end

  it "previews and imports account activity for the signed-in account" do
    path = Rails.root.join("test/fixtures/files/account_activity/preamble_card_activity.csv")
    upload = Rack::Test::UploadedFile.new(path, "text/csv", original_filename: "preamble_card_activity.csv")

    expect do
      post preview_account_account_activity_imports_path(account), params: { file: upload }
    end.not_to change(AccountActivity, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Activity Import Preview")
    expect(response.body).to include('aria-label="Breadcrumb"')
    expect(response.body).to include("Rewards Card")
    expect(response.body).to include("No account activity rows have been saved yet")
    expect(response.body).to include("Importing activity...")
    expect(response.body).to include("Import submitted")
    expect(response.body).to include("Institution balance found")
    preview_token = response.body[/name="preview_token"[^>]*value="([^"]+)"/, 1]
    expect(preview_token).to be_present

    expect do
      post account_account_activity_imports_path(account), params: { preview_token: preview_token }
    end.to change(OperationRun.where(operation_type: "commit_legacy_account_activity_import"), :count).by(1)
      .and change(AccountActivityImportDraft.where(account: account, state: "queued"), :count).by(1)
      .and have_enqueued_job(Accounts::ActivityImports::CommitJob)

    expect(AccountActivityImport.where(account: account)).to be_empty
    expect(AccountActivity.where(account: account)).to be_empty

    operation = OperationRun.find_by!(operation_type: "commit_legacy_account_activity_import")
    expect(response).to redirect_to(operation_run_path(operation))
    expect(flash[:notice]).to eq("Activity import queued. You can safely leave this page.")

    perform_enqueued_jobs(only: Accounts::ActivityImports::CommitJob)

    expect(operation.reload).to be_state_succeeded
    expect(operation).to have_attributes(progress_current: 3, progress_total: 3)
    expect(AccountActivityImport.where(account: account).count).to eq(1)
    expect(AccountActivity.where(account: account).count).to eq(197)
    expect(operation.account_activity_import_draft.reload).to be_state_consumed
    expect(operation.account_activity_import_draft.preview_payload).to eq({})
    activity_import = account.account_activity_imports.order(:created_at).last
    expect(activity_import.imported_at).to be_present
    expect(activity_import.institution_balance).to be_negative
    expect(activity_import.institution_balance_as_of).to eq(Date.new(2026, 6, 30))

    get account_path(account, view: "manage", anchor: "import-history")
    expect(response.body).to include("What has already been imported")
    expect(response.body).to include("Safest next export start")
    expect(response.body).to include("preamble_card_activity.csv")
  end

  it "shows prior coverage with an exact import time and flags a safe overlapping preview" do
    prior_import = create(
      :account_activity_import,
      account: account,
      original_filename: "previous-export.csv",
      started_on: Date.new(2026, 1, 1),
      ended_on: Date.new(2026, 12, 31),
      created_at: Time.zone.local(2026, 7, 1, 14, 35)
    )

    get new_account_account_activity_import_path(account)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("previous-export.csv")
    expect(response.body).to include(I18n.l(prior_import.imported_at, format: :long))
    expect(response.body).to include(I18n.l(prior_import.ended_on, format: :long))
    expect(response.body).to include("Include the last covered day again")

    path = Rails.root.join("test/fixtures/files/account_activity/positive_charges.csv")
    upload = Rack::Test::UploadedFile.new(path, "text/csv", original_filename: "positive_charges.csv")
    post preview_account_account_activity_imports_path(account), params: { file: upload }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Compared with your import log")
    expect(response.body).to include("overlaps 1 earlier import")
    expect(response.body).to include("will be skipped")
  end

  it "explains activity-only imports that do not include a trusted balance" do
    path = Rails.root.join("test/fixtures/files/account_activity/positive_charges.csv")
    upload = Rack::Test::UploadedFile.new(path, "text/csv", original_filename: "positive_charges.csv")

    post preview_account_account_activity_imports_path(account), params: { file: upload }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Activity-only import")
    expect(response.body).to include("needs an existing manual snapshot or future institution balance")
  end

  it "does not import another user's preview token into this user's account" do
    other_user = create(:user)
    other_account = create(:account, user: other_user)
    preview = {
      ok: true,
      account_id: other_account.id,
      file_digest: Digest::SHA256.hexdigest("other-user-import"),
      commit_idempotency_key: Digest::SHA256.hexdigest("other-user-commit"),
      rows_count: 0,
      imported_count: 0,
      duplicate_count: 0,
      rows: [],
      warnings: []
    }
    token = Accounts::ActivityImports::PreviewStore.new(user: other_user).store(preview)

    post account_account_activity_imports_path(account), params: { preview_token: token }

    expect(response).to redirect_to(new_account_account_activity_import_path(account))
    expect(flash[:alert]).to eq("Activity preview expired. Preview the file again before importing.")
  end

  it "rejects a nested preview token" do
    post account_account_activity_imports_path(account), params: { preview_token: { value: "invalid" } }

    expect(response).to have_http_status(:bad_request)
  end
end
