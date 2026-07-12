require "rails_helper"

RSpec.describe "account activity backup" do
  it "exports and imports account activity with the account activity scope" do
    user = create(:user)
    account = create(:account, user: user, name: "Rewards Card", kind: :credit_card)
    import = create(:account_activity_import, account: account, original_filename: "activity.csv")
    create(:account_activity, account_activity_import: import, account: account, description: "Sample Merchant")

    payload = Platform::UserDataExport.new(user: user, scopes: %w[accounts account_activity]).as_json

    expect(payload[:data][:account_activity].first[:account]).to eq("Rewards Card")
    expect(payload[:data][:account_activity].first[:account_activities].size).to eq(1)

    restored_user = create(:user)
    result = Platform::UserDataImport.new(user: restored_user, payload: payload, scopes: %w[accounts account_activity]).call

    expect(result).to include(success: true)
    restored_account = restored_user.accounts.find_by!(name: "Rewards Card")
    expect(restored_account.account_activity_imports.count).to eq(1)
    expect(restored_account.account_activities.first.description).to eq("Sample Merchant")
  end
end
