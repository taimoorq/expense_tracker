require "rails_helper"

RSpec.describe "Account activity imports", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user, name: "Rewards Card", kind: :credit_card) }

  before { sign_in user }

  it "describes the account activity import stages and pending preview state" do
    get new_account_account_activity_import_path(account)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import stages")
    expect(response.body).to include('aria-label="Breadcrumb"')
    expect(response.body).to include("Rewards Card")
    expect(response.body).to include("Import Activity")
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
    end.to change(AccountActivityImport.where(account: account), :count).by(1)
      .and change(AccountActivity.where(account: account), :count).by(197)

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to include("Activity import complete: 197 rows imported.")
    activity_import = account.account_activity_imports.order(:created_at).last
    expect(activity_import.institution_balance).to be_negative
    expect(activity_import.institution_balance_as_of).to eq(Date.new(2026, 6, 30))
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
      rows: [],
      warnings: []
    }
    token = Accounts::ActivityImports::PreviewStore.new(user: user).store(preview)

    post account_account_activity_imports_path(account), params: { preview_token: token }

    expect(response).to redirect_to(new_account_account_activity_import_path(account))
    expect(flash[:alert]).to eq("Activity preview does not match this account.")
  end
end
