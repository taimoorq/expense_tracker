require "rails_helper"

RSpec.describe "Account snapshots", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "updates an owned snapshot" do
    account = create(:account, user: user)
    snapshot = create(:account_snapshot, account: account, balance: 1200, notes: "Before")

    patch account_account_snapshot_path(account, snapshot), params: {
      account_snapshot: {
        recorded_on: "2026-03-14",
        balance: "1800.00",
        available_balance: "1750.00",
        notes: "After"
      }
    }

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to eq("Balance snapshot updated.")

    snapshot.reload
    expect(snapshot.balance.to_d).to eq(1800.to_d)
    expect(snapshot.available_balance.to_d).to eq(1750.to_d)
    expect(snapshot.notes).to eq("After")
  end

  it "deletes an owned snapshot" do
    account = create(:account, user: user)
    snapshot = create(:account_snapshot, account: account)

    expect do
      delete account_account_snapshot_path(account, snapshot)
    end.to change(AccountSnapshot, :count).by(-1)

    expect(response).to redirect_to(account_path(account))
    expect(flash[:notice]).to eq("Balance snapshot deleted.")
  end

  it "does not allow editing another user's snapshot" do
    other_account = create(:account)
    other_snapshot = create(:account_snapshot, account: other_account)

    patch account_account_snapshot_path(other_account, other_snapshot), params: {
      account_snapshot: { balance: "1.00", recorded_on: "2026-03-14" }
    }

    expect(response).to have_http_status(:not_found)
    expect(other_snapshot.reload.balance.to_d).not_to eq(1.to_d)
  end
end
