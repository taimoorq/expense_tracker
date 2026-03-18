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

  it "creates an entry and a planning template from the wizard payload" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-08",
          section: "fixed",
          category: "Streaming",
          payee: "Netflix",
          planned_amount: "19.99",
          account: "Checking",
          status: "planned",
          need_or_want: "Want",
          notes: "Family plan"
        },
        planning_template: {
          enabled: "1",
          template_type: "subscription",
          due_day: "8"
        }
      }
    end.to change(budget_month.expense_entries, :count).by(1)
      .and change(user.subscriptions, :count).by(1)

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(flash[:notice]).to eq("Entry and planning template added.")

    subscription = user.subscriptions.order(:created_at).last
    expect(subscription.name).to eq("Netflix")
    expect(subscription.amount.to_d).to eq(19.99.to_d)
    expect(subscription.due_day).to eq(8)
  end

  it "does not create the entry when the requested template is invalid" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-18",
          section: "debt",
          category: "Installment",
          payee: "IRS",
          planned_amount: "150.00",
          account: "Checking",
          status: "planned"
        },
        planning_template: {
          enabled: "1",
          template_type: "payment_plan",
          due_day: "18",
          total_due: ""
        }
      }
    end.not_to change(budget_month.expense_entries, :count)

    expect(user.payment_plans.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_entity)
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

  it "updates an entry with a linked source account" do
    entry = create(:expense_entry, budget_month: budget_month, user: user, account: "Custom Label")
    checking = create(:account, user: user, name: "Checking")

    patch budget_month_expense_entry_path(budget_month, entry), params: {
      expense_entry: { source_account_id: checking.id, account: "" }
    }

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(entry.reload.source_account).to eq(checking)
    expect(entry.account).to eq("Checking")
  end

  it "marks an entry as paid from the row action payload" do
    entry = create(:expense_entry, budget_month: budget_month, user: user, payee: "Internet", planned_amount: 65.25, actual_amount: nil, status: :planned)

    patch budget_month_expense_entry_path(budget_month, entry), params: {
      mark_as_paid: "1",
      expense_entry: { actual_amount: "" }
    }

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(entry.reload.status).to eq("paid")
    expect(entry.actual_amount.to_d).to eq(65.25.to_d)
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
