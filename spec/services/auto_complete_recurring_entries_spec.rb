require "rails_helper"

RSpec.describe AutoCompleteRecurringEntries, type: :service do
  describe "#call" do
    it "marks due recurring template entries as paid and copies planned to actual" do
      user = create(:user)
      month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

      due_subscription = create(
        :expense_entry,
        budget_month: month,
        user: user,
        occurred_on: Date.new(2026, 3, 10),
        planned_amount: 89.50,
        actual_amount: nil,
        status: :planned,
        source_file: "subscription"
      )
      future_subscription = create(
        :expense_entry,
        budget_month: month,
        user: user,
        occurred_on: Date.new(2026, 3, 20),
        planned_amount: 42,
        status: :planned,
        source_file: "subscription"
      )
      manual_entry = create(
        :expense_entry,
        budget_month: month,
        user: user,
        occurred_on: Date.new(2026, 3, 8),
        planned_amount: 25,
        status: :planned,
        source_file: "manual"
      )

      completed = described_class.new(entries: month.expense_entries, as_of: Date.new(2026, 3, 15)).call

      expect(completed).to eq(1)
      expect(due_subscription.reload).to be_paid
      expect(due_subscription.actual_amount.to_d).to eq(89.50)
      expect(future_subscription.reload).to be_planned
      expect(manual_entry.reload).to be_planned
    end

    it "preserves an existing actual amount when auto-completing" do
      user = create(:user)
      month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      paycheck = create(
        :expense_entry,
        budget_month: month,
        user: user,
        occurred_on: Date.new(2026, 3, 5),
        planned_amount: 2000,
        actual_amount: 2050,
        status: :planned,
        section: :income,
        source_file: "pay_schedule"
      )

      described_class.new(entries: month.expense_entries, as_of: Date.new(2026, 3, 15)).call

      expect(paycheck.reload).to be_paid
      expect(paycheck.actual_amount.to_d).to eq(2050)
    end
  end
end
