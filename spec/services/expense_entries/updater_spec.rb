require "rails_helper"

RSpec.describe ExpenseEntries::Updater do
  it "clears the auto-completed marker when a user saves the entry" do
    entry = create(:expense_entry, status: :paid, actual_amount: 125.50, auto_completed_at: 1.hour.ago)

    result = described_class.call(
      expense_entry: entry,
      params: {
        occurred_on: entry.occurred_on,
        section: entry.section,
        category: entry.category,
        payee: entry.payee,
        planned_amount: entry.planned_amount,
        actual_amount: "126.00",
        account: entry.account,
        status: "paid"
      },
      mark_as_paid: false
    )

    expect(result).to be(true)
    expect(entry.reload.auto_completed_at).to be_nil
    expect(entry.actual_amount.to_d).to eq(126)
  end

  it "moves an entry when its date changes to a month that already exists" do
    user = create(:user)
    march = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    april = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    entry = create(:expense_entry, budget_month: march, occurred_on: Date.new(2026, 3, 15))

    result = described_class.call(
      expense_entry: entry,
      params: { occurred_on: "2026-04-02" },
      mark_as_paid: false
    )

    expect(result).to be(true)
    expect(entry.reload.budget_month).to eq(april)
    expect(entry.occurred_on).to eq(Date.new(2026, 4, 2))
  end

  it "rejects a date change when the destination month does not exist" do
    user = create(:user)
    march = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    entry = create(:expense_entry, budget_month: march, occurred_on: Date.new(2026, 3, 15))

    result = described_class.call(
      expense_entry: entry,
      params: { occurred_on: "2026-04-02" },
      mark_as_paid: false
    )

    expect(result).to be(false)
    expect(entry.errors.full_messages).to include(
      "Date is outside March 2026. Create April 2026 first, or choose a date from March 1 through March 31."
    )
    expect(entry.reload.budget_month).to eq(march)
    expect(entry.occurred_on).to eq(Date.new(2026, 3, 15))
  end
end
