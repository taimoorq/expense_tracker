require "rails_helper"

RSpec.describe "Expense entries turbo responses", type: :request do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026") }
  let(:turbo_headers) { { "ACCEPT" => Mime[:turbo_stream].to_s } }

  before { sign_in user }

  it "returns turbo stream updates when creating an entry" do
    post budget_month_expense_entries_path(budget_month),
      params: {
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
    expect(response.body).to include('target="entries_table"')
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
    expect(response.body).to include('target="entries_table"')
    expect(response.body).to include('target="entry_editor_modal"')
    expect(response.body).to include("Entry updated.")
  end

  it "returns turbo stream updates when editing a generated template" do
    schedule = create(:pay_schedule, user: user, name: "Acme Payroll", amount: 2500, cadence: :monthly, first_pay_on: Date.new(2026, 1, 15), day_of_month_one: 15)
    entry = create(:expense_entry, budget_month: budget_month, user: user, payee: schedule.name, source_file: "pay_schedule", section: :income)

    patch update_template_budget_month_expense_entry_path(budget_month, entry),
      params: { pay_schedule: { amount: "3100.00" } },
      headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('target="template_editor_modal"')
    expect(response.body).to include("Recurring item updated.")
    expect(schedule.reload.amount.to_d).to eq(3100.to_d)
  end
end
