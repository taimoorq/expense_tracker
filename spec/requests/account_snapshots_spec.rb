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

    expect(response).to redirect_to(account_path(account, view: "manage"))
    expect(flash[:notice]).to eq("Balance snapshot updated.")

    snapshot.reload
    expect(snapshot.balance.to_d).to eq(1800.to_d)
    expect(snapshot.available_balance.to_d).to eq(1750.to_d)
    expect(snapshot.notes).to eq("After")
  end

  it "creates a missing balance source from the account row Turbo Frame" do
    account = create(:account, user: user, name: "Store Card", kind: :credit_card)
    activity_import = create(:account_activity_import, account: account)
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: Date.current, account_delta: -25)
    frame_id = ActionView::RecordIdentifier.dom_id(account, "desktop_snapshot_editor")

    get new_account_account_snapshot_path(account), headers: { "Turbo-Frame" => frame_id }

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML5.fragment(response.body)
    frame = document.at_css("turbo-frame##{frame_id}")
    expect(frame).to be_present
    expect(frame.text).to include("Add a balance for Store Card", "Imported rows are saved")

    expect do
      post account_account_snapshots_path(account),
        params: { account_snapshot: { recorded_on: Date.current.to_s, balance: "-450.00", notes: "Current card balance" } },
        headers: { "Turbo-Frame" => frame_id, "Accept" => Mime[:turbo_stream].to_s }
    end.to change(account.account_snapshots, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('action="refresh"')
    expect(response.body).not_to include("request-id")
    expect(account.account_snapshots.last.balance.to_d).to eq(-450.to_d)
  end

  it "renders inline snapshot validation errors in the requesting frame" do
    account = create(:account, user: user)
    snapshot = create(:account_snapshot, account: account, balance: 1200)
    frame_id = ActionView::RecordIdentifier.dom_id(account, "mobile_snapshot_editor")

    patch account_account_snapshot_path(account, snapshot),
      params: { account_snapshot: { recorded_on: "", balance: "" } },
      headers: { "Turbo-Frame" => frame_id, "Accept" => Mime[:turbo_stream].to_s }

    expect(response).to have_http_status(:unprocessable_content)
    document = Nokogiri::HTML5.fragment(response.body)
    frame = document.at_css("turbo-frame##{frame_id}")
    expect(frame).to be_present
    expect(frame.text).to include("Fix the snapshot details.", "Recorded on can't be blank", "Balance can't be blank")
  end

  it "deletes an owned snapshot" do
    account = create(:account, user: user)
    snapshot = create(:account_snapshot, account: account)

    expect do
      delete account_account_snapshot_path(account, snapshot)
    end.to change(AccountSnapshot, :count).by(-1)

    expect(response).to redirect_to(account_path(account, view: "manage"))
    expect(flash[:notice]).to eq("Balance snapshot deleted.")
  end

  it "renders the manage path with validation errors when a snapshot is invalid" do
    account = create(:account, user: user)

    post account_account_snapshots_path(account), params: {
      account_snapshot: { recorded_on: "", balance: "" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Fix the snapshot details.")
    expect(response.body).to include("Monthly balance history")
    expect(response.body).to include('aria-current="page"')
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
