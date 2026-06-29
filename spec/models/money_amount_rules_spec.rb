require "rails_helper"

RSpec.describe "Money amount rules", type: :model do
  it "keeps budget entry amounts non-negative because section controls direction" do
    entry = build(:expense_entry, planned_amount: -1, actual_amount: -2)

    expect(entry).not_to be_valid
    expect(entry.errors[:planned_amount]).to include("must be greater than or equal to 0")
    expect(entry.errors[:actual_amount]).to include("must be greater than or equal to 0")
  end

  it "requires recurring income and subscription amounts to be positive" do
    schedule = build(:pay_schedule, amount: 0)
    subscription = build(:subscription, amount: -1)

    expect(schedule).not_to be_valid
    expect(schedule.errors[:amount]).to include("must be greater than 0")
    expect(subscription).not_to be_valid
    expect(subscription.errors[:amount]).to include("must be greater than 0")
  end

  it "allows zero monthly bills and card minimums but not negative values" do
    bill = build(:monthly_bill, default_amount: 0)
    card = build(:credit_card, minimum_payment: 0)
    negative_bill = build(:monthly_bill, default_amount: -1)
    negative_card = build(:credit_card, minimum_payment: -1)

    expect(bill).to be_valid
    expect(card).to be_valid
    expect(negative_bill).not_to be_valid
    expect(negative_card).not_to be_valid
  end

  it "keeps payment plan totals positive and progress within the plan balance" do
    zero_total = build(:payment_plan, total_due: 0)
    negative_progress = build(:payment_plan, amount_paid: -1)
    overpaid = build(:payment_plan, total_due: 100, amount_paid: 101)

    expect(zero_total).not_to be_valid
    expect(zero_total.errors[:total_due]).to include("must be greater than 0")
    expect(negative_progress).not_to be_valid
    expect(negative_progress.errors[:amount_paid]).to include("must be greater than or equal to 0")
    expect(overpaid).not_to be_valid
    expect(overpaid.errors[:amount_paid]).to include("must be less than or equal to total due")
  end

  it "allows account snapshots to cross zero while still requiring numeric balances" do
    negative_snapshot = build(:account_snapshot, balance: -125.50, available_balance: 0)
    invalid_snapshot = build(:account_snapshot, balance: "not money")

    expect(negative_snapshot).to be_valid
    expect(invalid_snapshot).not_to be_valid
    expect(invalid_snapshot.errors[:balance]).to include("is not a number")
  end
end
