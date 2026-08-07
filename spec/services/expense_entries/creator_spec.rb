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
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

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
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

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

    it "rejects an entry date outside the selected month" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 4, 1),
          section: "fixed",
          category: "Rent",
          payee: "Landlord",
          planned_amount: "1,200.00",
          status: "planned"
        },
        planning_template_params: {},
        recurring_link_token: nil
      )

      expect(result).not_to be_success
      expect(result.expense_entry).not_to be_persisted
      expect(result.expense_entry.errors.full_messages).to include(
        "Date must be in March 2026 (March 1 through March 31)"
      )
    end

    it "requires the core fields used by the interactive entry composer" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          section: "fixed",
          category: "",
          payee: "",
          planned_amount: "",
          actual_amount: "",
          status: "planned"
        },
        planning_template_params: {},
        recurring_link_token: nil
      )

      expect(result).not_to be_success
      expect(result.expense_entry.errors.full_messages).to include(
        "Date choose a date",
        "Category choose a category",
        "Payee enter who this is with",
        "Amount enter a planned or actual amount"
      )
    end

    it "rejects using the same account as both sides of a movement" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      checking = create(:account, user: user, kind: :checking)

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 8),
          section: "debt",
          category: "Credit card payment",
          payee: "Card payment",
          planned_amount: "125.00",
          source_account_id: checking.id,
          destination_account_id: checking.id,
          status: "planned"
        },
        planning_template_params: {},
        recurring_link_token: nil
      )

      expect(result).not_to be_success
      expect(result.expense_entry.errors.full_messages).to include("Money goes to must be different from Money comes from")
    end

    it "rejects linking an existing recurring source while creating a new one" do
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
          status: "planned"
        },
        planning_template_params: { enabled: "1", template_type: "subscription" },
        recurring_link_token: "Subscription:#{subscription.id}"
      )

      expect(result).not_to be_success
      expect(result.expense_entry.errors.full_messages).to include(
        "Recurring transaction choose an existing recurring item or create a new one, not both"
      )
    end

    it "links a newly created recurring template back to the saved entry" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      checking = create(:account, user: user, kind: :checking, name: "Everyday checking")

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 8),
          section: "fixed",
          category: "Streaming",
          payee: "Netflix",
          planned_amount: "19.99",
          source_account_id: checking.id,
          status: "planned",
          source_file: "manual"
        },
        planning_template_params: { enabled: "1", template_type: "subscription", due_day: "8" },
        recurring_link_token: nil
      )

      expect(result).to be_success
      expect(result.message).to eq("Entry and recurring transaction added.")
      expect(result.expense_entry.source_template).to be_a(Subscription)
      expect(result.expense_entry.source_template).to be_persisted
      expect(result.expense_entry.source_template.linked_account).to eq(checking)
      expect(result.expense_entry.source_file).to eq("manual")
      expect(result.expense_entry).to be_template_linked
      expect(result.expense_entry).not_to be_generated_from_template
    end

    it "copies the planned amount into the actual amount when a paid entry is created" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 8),
          section: "fixed",
          category: "Utilities",
          payee: "Power Co",
          planned_amount: "125.00",
          actual_amount: "",
          status: "paid"
        },
        planning_template_params: {},
        recurring_link_token: nil
      )

      expect(result).to be_success
      expect(result.expense_entry.actual_amount).to eq(125.to_d)
    end

    it "does not mutate payment plan progress when a paid entry is linked" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      payment_plan = create(:payment_plan, user: user, amount_paid: 200, monthly_target: 150, due_day: 20)

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 20),
          section: "debt",
          category: "Payment Plan",
          payee: payment_plan.name,
          planned_amount: "150.00",
          status: "paid"
        },
        planning_template_params: {},
        recurring_link_token: "PaymentPlan:#{payment_plan.id}"
      )

      expect(result).to be_success
      expect(result.expense_entry.source_template).to eq(payment_plan)
      expect(payment_plan.reload.amount_paid).to eq(200.to_d)
    end

    it "requires explicit confirmation before adding another occurrence of a covered recurring item" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      subscription = create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8)
      create(
        :expense_entry,
        budget_month: budget_month,
        occurred_on: Date.new(2026, 3, 8),
        section: :fixed,
        category: "Subscription",
        payee: "Netflix",
        planned_amount: 19.99,
        account: subscription.account,
        source_file: "subscription",
        source_template: subscription
      )
      attributes = {
        occurred_on: Date.new(2026, 3, 20),
        section: "fixed",
        category: "Subscription",
        payee: "Netflix",
        planned_amount: "19.99",
        status: "planned"
      }

      blocked_result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: attributes,
        planning_template_params: {},
        recurring_link_token: "Subscription:#{subscription.id}"
      )
      confirmed_result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: attributes,
        planning_template_params: {},
        recurring_link_token: "Subscription:#{subscription.id}",
        recurring_extra_occurrence: "1"
      )

      expect(blocked_result).not_to be_success
      expect(blocked_result.expense_entry.errors.full_messages).to include("Extra occurrence confirm that this is an extra occurrence")
      expect(confirmed_result).to be_success
    end

    it "explains when a new recurring type cannot preserve a destination account" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      checking = create(:account, user: user, kind: :checking)
      card = create(:account, user: user, kind: :credit_card)

      result = described_class.call(
        user: user,
        budget_month: budget_month,
        expense_entry_params: {
          occurred_on: Date.new(2026, 3, 18),
          section: "debt",
          category: "Payment plan",
          payee: "Card payoff",
          planned_amount: "150.00",
          source_account_id: checking.id,
          destination_account_id: card.id,
          status: "planned"
        },
        planning_template_params: { enabled: "1", template_type: "payment_plan", total_due: "1,000", due_day: "18" },
        recurring_link_token: nil
      )

      expect(result).not_to be_success
      expect(result.expense_entry.errors.full_messages).to include(
        "Recurring transaction cannot carry the Money goes to account for a new recurring item; save this as one-time or link an existing credit card"
      )
    end
  end
end
