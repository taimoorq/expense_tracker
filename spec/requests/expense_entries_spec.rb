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

    expect(response).to redirect_to(budget_month_tab_path(budget_month, "entries"))
    expect(budget_month.expense_entries.last.user).to eq(user)
  end

  it "creates an entry and a recurring transaction from the wizard payload" do
    checking = create(:account, user: user, name: "Checking", kind: :checking)

    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-08",
          section: "fixed",
          category: "Streaming",
          payee: "Netflix",
          planned_amount: "19.99",
          source_account_id: checking.id,
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

    expect(response).to redirect_to(budget_month_tab_path(budget_month, "entries"))
    expect(flash[:notice]).to eq("Entry and recurring transaction added.")

    subscription = user.subscriptions.order(:created_at).last
    expect(subscription.name).to eq("Netflix")
    expect(subscription.amount.to_d).to eq(19.99.to_d)
    expect(subscription.due_day).to eq(8)
    expect(subscription.linked_account).to eq(checking)
  end

  it "creates a monthly bill template with explicit billing months from the wizard payload" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-07-15",
          section: "fixed",
          category: "Housing",
          payee: "HOA",
          planned_amount: "600.00",
          account: "Checking",
          status: "planned",
          need_or_want: "Need",
          notes: "Twice a year"
        },
        planning_template: {
          enabled: "1",
          template_type: "monthly_bill",
          due_day: "15",
          kind: "fixed_payment",
          billing_frequency: "semiannual",
          billing_months: [ "1", "7" ]
        }
      }
    end.to change(budget_month.expense_entries, :count).by(1)
      .and change(user.monthly_bills, :count).by(1)

    bill = user.monthly_bills.order(:created_at).last
    expect(bill.name).to eq("HOA")
    expect(bill.billing_frequency).to eq("semiannual")
    expect(bill.billing_months).to eq([ 1, 7 ])
  end

  it "creates a wizard entry linked to an existing recurring transaction" do
    credit_card = create(:credit_card, user: user, name: "Visa", minimum_payment: 75, due_day: 21, active: true)

    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        recurring_link: "CreditCard:#{credit_card.id}",
        expense_entry: {
          occurred_on: "2026-03-22",
          section: "debt",
          category: "Credit Card",
          payee: "Visa",
          planned_amount: "125.00",
          account: "Checking",
          status: "planned",
          need_or_want: "Need",
          notes: "Extra payment"
        }
      }
    end.to change { budget_month.expense_entries.reload.count }.by(1)

    entry = budget_month.expense_entries.order(:created_at).last

    expect(response).to redirect_to(budget_month_tab_path(budget_month, "entries"))
    expect(entry.source_template).to eq(credit_card)
    expect(entry.source_file).to eq("manual")
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
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects wizard recurring template types that are not exposed by the server contract" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-21",
          section: "fixed",
          category: "Credit Card",
          payee: "Rewards Visa",
          planned_amount: "125.00",
          account: "Checking",
          status: "planned"
        },
        planning_template: {
          enabled: "1",
          template_type: "credit_card",
          due_day: "21"
        }
      }
    end.not_to change { budget_month.expense_entries.reload.count }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Recurring: choose what should repeat.")
  end

  it "rejects wizard recurring template types that are unsupported for the entry section" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-15",
          section: "income",
          category: "Paycheck",
          payee: "Acme Payroll",
          planned_amount: "3000.00",
          account: "Checking",
          status: "planned"
        },
        planning_template: {
          enabled: "1",
          template_type: "subscription",
          due_day: "15"
        }
      }
    end.not_to change { budget_month.expense_entries.reload.count }

    expect(user.subscriptions.reload.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Recurring: Subscription is not available for income entries.")
  end

  it "rejects wizard monthly bill billing months that do not match the selected frequency" do
    expect do
      post budget_month_expense_entries_path(budget_month), params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-12",
          section: "fixed",
          category: "Utilities",
          payee: "Water District",
          planned_amount: "80.00",
          account: "Checking",
          status: "planned"
        },
        planning_template: {
          enabled: "1",
          template_type: "monthly_bill",
          due_day: "12",
          kind: "fixed_payment",
          billing_frequency: "quarterly",
          billing_months: [ "1", "7" ]
        }
      }
    end.not_to change { budget_month.expense_entries.reload.count }

    expect(user.monthly_bills.reload.count).to eq(0)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Recurring: Billing months must include 4 months for quarterly")
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

  it "moves an entry to the budget month matching its edited date" do
    next_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    entry = create(:expense_entry, budget_month: budget_month, user: user, occurred_on: Date.new(2026, 3, 20), payee: "Power Co")

    expect do
      patch budget_month_expense_entry_path(budget_month, entry), params: {
        expense_entry: { occurred_on: "2026-04-03" }
      }
    end.to change { budget_month.expense_entries.reload.count }.by(-1)
      .and change { next_month.expense_entries.reload.count }.by(1)

    expect(response).to redirect_to(budget_month_tab_path(next_month, "entries"))
    expect(flash[:notice]).to eq("Entry moved to April 2026.")
    expect(entry.reload.budget_month).to eq(next_month)
    expect(entry.occurred_on).to eq(Date.new(2026, 4, 3))
  end

  it "rejects an edited date outside the month when that budget month does not exist" do
    entry = create(:expense_entry, budget_month: budget_month, user: user, occurred_on: Date.new(2026, 3, 20))

    patch budget_month_expense_entry_path(budget_month, entry),
      params: {
        expense_entry: { occurred_on: "2026-04-03" }
      },
      headers: { "ACCEPT" => Mime[:turbo_stream].to_s }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include("Create April 2026 first")
    expect(entry.reload.budget_month).to eq(budget_month)
    expect(entry.occurred_on).to eq(Date.new(2026, 3, 20))
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
