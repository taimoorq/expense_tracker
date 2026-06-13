require "rails_helper"

RSpec.describe Accounts::Creator do
  it "creates a credit card account with an optional snapshot and monthly payment schedule" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)

    result = described_class.call(
      user: user,
      account_params: {
        name: "Visa Rewards",
        institution_name: "Chase",
        kind: "credit_card",
        active: "1",
        include_in_net_worth: "1",
        include_in_cash: "0"
      },
      initial_snapshot_params: {
        recorded_on: "2026-06-01",
        balance: "-1200.00",
        available_balance: "",
        notes: "Opening card balance"
      },
      credit_card_payment_schedule_params: {
        enabled: "1",
        payment_account_id: checking.id,
        minimum_payment: "85.00",
        due_day: "18",
        priority: "2",
        active: "1",
        notes: "Autopay"
      }
    )

    expect(result).to be_success

    account = user.accounts.find_by!(name: "Visa Rewards")
    schedule = user.credit_cards.find_by!(name: "Visa Rewards")

    expect(account).to be_credit_card
    expect(account.account_snapshots.first.balance.to_d).to eq(-1200.to_d)
    expect(schedule.linked_account).to eq(account)
    expect(schedule.payment_account).to eq(checking)
    expect(schedule.account).to eq("Checking")
    expect(schedule.minimum_payment.to_d).to eq(85.to_d)
    expect(schedule.due_day).to eq(18)
    expect(schedule.priority).to eq(2)
  end

  it "ignores schedule params for non-credit-card accounts" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)

    expect do
      result = described_class.call(
        user: user,
        account_params: {
          name: "Vacation Savings",
          kind: "savings",
          active: "1",
          include_in_net_worth: "1",
          include_in_cash: "1"
        },
        initial_snapshot_params: {},
        credit_card_payment_schedule_params: {
          enabled: "1",
          payment_account_id: checking.id,
          minimum_payment: "50.00",
          due_day: "12",
          priority: "1",
          active: "1"
        }
      )

      expect(result).to be_success
    end.to change { user.accounts.count }.by(1)
      .and change { user.credit_cards.count }.by(0)
  end

  it "does not persist the account when the requested schedule is invalid" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)

    expect do
      result = described_class.call(
        user: user,
        account_params: {
          name: "Store Card",
          kind: "credit_card",
          active: "1",
          include_in_net_worth: "1",
          include_in_cash: "0"
        },
        initial_snapshot_params: {},
        credit_card_payment_schedule_params: {
          enabled: "1",
          payment_account_id: checking.id,
          minimum_payment: "",
          due_day: "30",
          priority: "1",
          active: "1"
        }
      )

      expect(result).not_to be_success
      expect(result.credit_card_payment_schedule.errors[:minimum_payment]).to be_present
    end.to change { user.accounts.count }.by(0)
      .and change { user.credit_cards.count }.by(0)
  end
end
