require "rails_helper"

RSpec.describe ExpenseEntries::Creator do
  describe ".call" do
    it "creates an entry and links an existing recurring source from the token" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      subscription = create(:subscription, user: user, name: "Netflix")

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 8),
          section: "fixed",
          category: "Streaming",
          payee: "Netflix",
          planned_amount: "19.99",
          account: "Checking",
          status: "planned"
        },
        planning_template_params: {},
        recurring_link_token: "Subscription:#{subscription.id}"
      )

      expect(result).to be_success
      expect(result.message).to eq("Entry added.")
      expect(result.expense_entry).to be_persisted
      expect(result.expense_entry.source_template).to eq(subscription)
    end

    it "returns a rebuilt unsaved entry with validation errors when the recurring token is invalid" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 8),
          section: "fixed",
          category: "Streaming",
          payee: "Netflix",
          planned_amount: "19.99",
          account: "Checking",
          status: "planned"
        },
        planning_template_params: {},
        recurring_link_token: "Subscription:999999"
      )

      expect(result.success?).to be(false)
      expect(result.expense_entry).not_to be_persisted
      expect(result.expense_entry.errors.full_messages).to include("Choose a valid recurring transaction to link.")
    end

    it "rolls back the entry when template creation fails and keeps the recurring error on the rebuilt entry" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 18),
          section: "debt",
          category: "Installment",
          payee: "IRS",
          planned_amount: "150.00",
          account: "Checking",
          status: "planned"
        },
        planning_template_params: {
          enabled: "1",
          template_type: "payment_plan",
          due_day: "18",
          total_due: ""
        },
        recurring_link_token: nil
      )

      expect(result.success?).to be(false)
      expect(result.expense_entry).not_to be_persisted
      expect(budget_month.expense_entries.count).to eq(0)
      expect(result.expense_entry.errors.full_messages).to include("Recurring: Total due can't be blank")
    end
  end
end
