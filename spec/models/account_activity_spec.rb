require "rails_helper"

RSpec.describe AccountActivity, type: :model do
  it "requires activity to stay inside one user's account and import" do
    user = create(:user)
    other_user = create(:user)
    account = create(:account, user: user)
    import = create(:account_activity_import, account: account)
    other_account = create(:account, user: other_user)

    activity = build(:account_activity, account_activity_import: import, account: other_account, user: other_user)

    expect(activity).not_to be_valid
    expect(activity.errors[:account_activity_import]).to include("must belong to the same account")
  end
end
