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
end
