require "rails_helper"

RSpec.describe "Expense entries", type: :request do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026") }

  before { sign_in user }

  it "creates an entry for the signed in user's month" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        expense_entry: {
          occurred_on: "2026-03-05",
          section: "fixed",
          category: "Utilities",
          payee: "Pepco",
          planned_amount: "89.33",
          account: "Checking",
          status: "planned",
          need_or_want: "Need",
          notes: "Electric"
        }
      }
    end.to change(budget_month.expense_entries, :count).by(1)

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(budget_month.expense_entries.last.user).to eq(user)
  end

  it "updates an entry in the signed in user's month" do
    entry = create(:expense_entry, budget_month: budget_month, user: user, payee: "Old Payee")

    patch budget_month_expense_entry_path(budget_month, entry), params: {
      expense_entry: { payee: "New Payee", actual_amount: "42.50", status: "paid" }
    }

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(entry.reload.payee).to eq("New Payee")
    expect(entry.status).to eq("paid")
  end

  it "deletes an entry in the signed in user's month" do
    entry = create(:expense_entry, budget_month: budget_month, user: user)

    expect do
      delete budget_month_expense_entry_path(budget_month, entry)
    end.to change(budget_month.expense_entries, :count).by(-1)

    expect(response).to redirect_to(budget_month_path(budget_month))
  end

  it "does not allow editing another user's entry" do
    other_user = create(:user)
    other_month = create(:budget_month, user: other_user)
    other_entry = create(:expense_entry, budget_month: other_month, user: other_user)

    patch budget_month_expense_entry_path(other_month, other_entry), params: {
      expense_entry: { payee: "Nope" }
    }

    expect(response).to have_http_status(:not_found)
  end
end