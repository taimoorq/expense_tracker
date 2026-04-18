require "rails_helper"

RSpec.describe Budgeting::TimelinePresenter do
  describe "#groups_for_view" do
    it "builds grouped rows with the expected actions and reason pills" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      account = create(:account, user: user, name: "Checking")
      pay_schedule = create(:pay_schedule, user: user, name: "Employer", linked_account: account)

      income_entry = create(
        :expense_entry,
        budget_month: budget_month,
        user: user,
        occurred_on: Date.new(2026, 3, 15),
        section: :income,
        category: "Paycheck",
        payee: "Employer",
        planned_amount: 2500,
        source_file: "pay_schedule",
        source_template: pay_schedule
      )
      other_entry = create(
        :expense_entry,
        budget_month: budget_month,
        user: user,
        occurred_on: Date.new(2026, 3, 20),
        section: :other,
        category: nil,
        payee: "Parking",
        planned_amount: 25,
        actual_amount: 30,
        source_account: account,
        source_file: "manual"
      )

      presenter = described_class.new(
        budget_month: budget_month,
        expense_entries: budget_month.expense_entries,
        default_timeline_view: "calendar"
      )

      expect(presenter.timeline_leftover).to eq(budget_month.calculated_leftover)
      expect(presenter.reason_pills).to include([ "Other", 1 ], [ "Paycheck", 1 ])

      income_group, other_group = presenter.groups_for_view
      expect(income_group[:name]).to eq("Income & Paychecks")
      expect(income_group[:rows].first[:payee]).to eq("Employer")
      expect(income_group[:rows].first[:generated_from_template]).to be(true)
      expect(income_group[:rows].first[:edit_path]).to include("/budget_months/#{budget_month.id}/expense_entries/#{income_entry.id}/edit")

      expect(other_group[:name]).to eq("Other")
      expect(other_group[:show_reason_column]).to be(true)
      expect(other_group[:rows].first[:account_name]).to eq("Checking")
      expect(other_group[:rows].first[:reason]).to eq("Other")
      expect(other_group[:rows].first[:mark_as_paid_params]).to include(timeline_view: "calendar")
    end
  end
end
