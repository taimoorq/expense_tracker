require "rails_helper"

RSpec.describe "Budget month cloning", type: :request do
  let(:user) { create(:user) }
  let(:source_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026") }

  before do
    sign_in user
    create(:expense_entry,
      budget_month: source_month,
      user: user,
      occurred_on: Date.new(2026, 3, 14),
      payee: "Internet",
      planned_amount: 75,
      actual_amount: 78,
      status: :paid,
      source_file: "manual")
  end

  it "clones entries into a new month with shifted dates and reset actuals/status" do
    expect do
      post budget_months_path, params: {
        source_month_id: source_month.id,
        budget_month: {
          month_on: "2026-04-01",
          label: "April 2026"
        }
      }
    end.to change(user.budget_months, :count).by(1)
       .and change(ExpenseEntry.where(user: user), :count).by(1)

    cloned_month = user.budget_months.find_by!(label: "April 2026")
    cloned_entry = cloned_month.expense_entries.find_by!(payee: "Internet")

    expect(response).to redirect_to(budget_month_path(cloned_month))
    expect(cloned_entry.occurred_on).to eq(Date.new(2026, 4, 14))
    expect(cloned_entry.planned_amount.to_d).to eq(78.to_d)
    expect(cloned_entry.actual_amount).to be_nil
    expect(cloned_entry.status).to eq("planned")
  end
end