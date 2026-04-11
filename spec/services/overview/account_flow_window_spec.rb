require "rails_helper"

RSpec.describe Overview::AccountFlowWindow do
  it "limits the account flow summary to the selected recent months" do
    user = create(:user)
    current_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    previous_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    checking = create(:account, user: user, name: "Checking")
    visa = create(:account, user: user, name: "Visa")

    create(:expense_entry, budget_month: current_month, user: user, section: :income, payee: "Employer", planned_amount: 3_000, source_account: checking)
    create(:expense_entry, budget_month: previous_month, user: user, section: :variable, payee: "Streaming", planned_amount: 35, source_account: visa)

    latest_month_payload = described_class.new(user: user, month_window: "1").call
    all_months_payload = described_class.new(user: user, month_window: "all").call

    expect(latest_month_payload[:account_flow_months_included]).to eq(1)
    expect(latest_month_payload[:account_flow_month_range_label]).to eq("April 2026")
    expect(latest_month_payload[:account_flow_payload][:labels]).to eq([ "Checking" ])

    expect(all_months_payload[:account_flow_months_included]).to eq(2)
    expect(all_months_payload[:account_flow_month_range_label]).to eq("March 2026 to April 2026")
    expect(all_months_payload[:account_flow_payload][:labels]).to eq([ "Checking", "Visa" ])
  end
end
