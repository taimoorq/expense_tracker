require "rails_helper"

RSpec.describe Budgeting::EntryWizardPresenter do
  describe "#selected_billing_months" do
    it "falls back to the default months for the chosen billing frequency" do
      month = build_stubbed(:budget_month)
      entry = build_stubbed(:expense_entry, occurred_on: Date.new(2026, 4, 9))

      presenter = described_class.new(
        budget_month: month,
        expense_entry: entry,
        params: {
          planning_template: {
            billing_frequency: "semiannual",
            billing_months: [ "" ]
          }
        },
        wizard_steps: []
      )

      expect(presenter.selected_billing_frequency).to eq("semiannual")
      expect(presenter.selected_billing_months).to eq([ 1, 7 ])
    end
  end

  describe "#selected_recurring_link" do
    it "reuses the linked source template when no explicit token was submitted" do
      user = create(:user)
      template = create(:subscription, user: user)
      month = build_stubbed(:budget_month, user: user)
      entry = build_stubbed(:expense_entry, budget_month: month, user: user)
      allow(entry).to receive(:source_template).and_return(template)

      presenter = described_class.new(
        budget_month: month,
        expense_entry: entry,
        params: {},
        wizard_steps: []
      )

      expect(presenter.selected_recurring_link).to eq("Subscription:#{template.id}")
    end
  end

  describe "#selected_day_of_month_one" do
    it "falls back to the entry date when no template day is provided" do
      month = build_stubbed(:budget_month)
      entry = build_stubbed(:expense_entry, occurred_on: Date.new(2026, 4, 18))

      presenter = described_class.new(
        budget_month: month,
        expense_entry: entry,
        params: {},
        wizard_steps: []
      )

      expect(presenter.selected_due_day).to eq(18)
      expect(presenter.selected_day_of_month_one).to eq(18)
    end
  end
end
