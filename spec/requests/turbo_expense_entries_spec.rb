require "rails_helper"

RSpec.describe "Expense entries turbo responses", type: :request do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026") }
  let(:turbo_headers) { { "ACCEPT" => Mime[:turbo_stream].to_s } }

  before { sign_in user }

  it "returns turbo stream updates when creating an entry" do
    post budget_month_expense_entries_path(budget_month),
      params: {
        wizard_flow: "1",
        expense_entry: {
          occurred_on: "2026-03-11",
          section: "fixed",
          category: "Utilities",
          payee: "Pepco",
          planned_amount: "91.00",
          status: "planned"
        }
      },
      headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('target="flash"')
    expect(response.body).to include('target="timeline_section"')
    expect(response.body).to include("Entry added.")
  end

  it "returns turbo stream updates when updating an entry" do
    entry = create(:expense_entry, budget_month: budget_month, user: user, payee: "Pepco", planned_amount: 91, status: :planned)

    patch budget_month_expense_entry_path(budget_month, entry),
      params: {
        expense_entry: {
          payee: "Updated Pepco",
          actual_amount: "91.00",
          status: "paid"
        }
      },
      headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('target="month_summary"')
    expect(response.body).to include('target="timeline_section"')
    expect(response.body).to include('target="entry_editor_modal"')
    expect(response.body).to include("Entry updated.")
  end

  it "redirects to the destination month when an edited date moves the entry" do
    next_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    entry = create(:expense_entry, budget_month: budget_month, user: user, occurred_on: Date.new(2026, 3, 20))

    patch budget_month_expense_entry_path(budget_month, entry),
      params: {
        expense_entry: {
          occurred_on: "2026-04-03"
        }
      },
      headers: turbo_headers

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(budget_month_tab_path(next_month, "entries"))
    expect(entry.reload.budget_month).to eq(next_month)
  end

  it "returns turbo stream updates when editing a generated template" do
    schedule = create(:pay_schedule, user: user, name: "Acme Payroll", amount: 2500, cadence: :monthly, first_pay_on: Date.new(2026, 1, 15), day_of_month_one: 15)
    entry = create(:expense_entry, budget_month: budget_month, user: user, payee: schedule.name, source_file: "pay_schedule", section: :income, source_template: schedule)

    patch update_template_budget_month_expense_entry_path(budget_month, entry),
      params: { pay_schedule: { amount: "3100.00" } },
      headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('target="template_editor_modal"')
    expect(response.body).to include("Recurring item updated.")
    expect(schedule.reload.amount.to_d).to eq(3100.to_d)
  end

  it "updates the paid-from account when editing a generated credit card template" do
    card_account = create(:account, user: user, name: "Visa Account", kind: :credit_card)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    savings = create(:account, user: user, name: "Savings", kind: :savings)
    card = create(:credit_card, user: user, name: "Visa", linked_account: card_account, payment_account: checking, account: "Checking")
    entry = create(:expense_entry, budget_month: budget_month, user: user, payee: card.name, source_file: "credit_card_estimate", section: :debt, source_template: card, source_account: checking)

    patch update_template_budget_month_expense_entry_path(budget_month, entry),
      params: { credit_card: { payment_account_id: savings.id } },
      headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include("Recurring item updated.")
    expect(card.reload.payment_account).to eq(savings)
  end
end
