require "rails_helper"

RSpec.describe Budgeting::MonthCreator do
  describe ".call" do
    it "creates a fresh month and reports imported templates when generation is enabled" do
      user = create(:user)
      allow_any_instance_of(Recurring::GenerateMonthPaychecks).to receive(:call).and_return(1)
      allow_any_instance_of(Recurring::GenerateMonthSubscriptions).to receive(:call).and_return(2)
      allow_any_instance_of(Recurring::GenerateMonthMonthlyBills).to receive(:call).and_return(0)
      allow_any_instance_of(Recurring::GenerateMonthPaymentPlans).to receive(:call).and_return(0)
      allow_any_instance_of(Recurring::EstimateMonthCreditCards).to receive(:call).and_return(0)

      result = described_class.call(
        user: user,
        budget_month_params: { month_on: Date.new(2026, 6, 1), label: "" },
        month_workflow: "fresh",
        source_budget_month: nil,
        include_applicable_templates: true
      )

      expect(result).to be_success
      expect(result.budget_month).to be_persisted
      expect(result.budget_month.label).to eq("June 2026")
      expect(result.notice).to eq("Budget month created. Imported 3 planning templates for this month.")
      expect(result.wizard_step).to be_nil
    end

    it "fails clone workflow when no source month is selected" do
      user = create(:user)

      result = described_class.call(
        user: user,
        budget_month_params: {},
        month_workflow: "clone",
        source_budget_month: nil,
        include_applicable_templates: false
      )

      expect(result.success?).to be(false)
      expect(result.budget_month.errors.full_messages).to include("Choose a month to clone before continuing.")
      expect(result.wizard_step).to eq(0)
    end

    it "clones entries into the next available month and skips credit card estimate rows" do
      user = create(:user)
      source_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026", notes: "From March")
      create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
      kept_entry = create(
        :expense_entry,
        budget_month: source_month,
        user: user,
        occurred_on: Date.new(2026, 3, 31),
        payee: "Internet",
        planned_amount: 75,
        actual_amount: 80,
        source_file: "manual",
        status: :paid
      )
      create(
        :expense_entry,
        budget_month: source_month,
        user: user,
        payee: "Visa",
        planned_amount: 150,
        source_file: CreditCard.template_source_file
      )

      result = described_class.call(
        user: user,
        budget_month_params: {},
        month_workflow: "clone",
        source_budget_month: source_month,
        include_applicable_templates: false
      )

      expect(result).to be_success
      expect(result.budget_month.month_on).to eq(Date.new(2026, 5, 1))
      expect(result.budget_month.notes).to eq("From March")
      expect(result.notice).to eq("Budget month created and 1 entries cloned from March 2026.")

      cloned_entry = result.budget_month.expense_entries.find_by!(payee: kept_entry.payee)
      expect(cloned_entry.occurred_on).to eq(Date.new(2026, 5, 31))
      expect(cloned_entry.planned_amount.to_d).to eq(80.to_d)
      expect(cloned_entry.actual_amount).to be_nil
      expect(cloned_entry.status).to eq("planned")
      expect(result.budget_month.expense_entries.where(payee: "Visa")).to be_empty
    end
  end
end
