require "rails_helper"

RSpec.describe Overview::PageData do
  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  it "returns a consolidated overview payload with next-step guidance" do
    user = create(:user)
    account = create(:account, user:, name: "Checking", kind: :checking)
    create(:account_snapshot, account:, recorded_on: Date.current, balance: 1_500)
    create(:pay_schedule, user:, name: "Salary", amount: 2_000, first_pay_on: Date.current.beginning_of_month, linked_account: account)
    month = create(:budget_month, user:, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, user:, budget_month: month, section: :income, payee: "Employer A", planned_amount: 2_000, status: :paid, source_account: account)

    payload = described_class.new(user:).call

    expect(payload[:current_month]).to eq(month)
    expect(payload[:accounts]).to include(account)
    expect(payload[:template_total]).to eq(1)
    expect(payload[:linked_template_total]).to eq(1)
    expect(payload[:account_flow_month_window]).to eq("3")
    expect(payload[:account_flow_months_included]).to eq(1)
    expect(payload[:account_flow_month_range_label]).to eq(month.label)
    expect(payload[:account_flow_payload]).to include(:labels, :charged_total, :paid_total)
    expect(payload[:year_cashflow_payload]).to include(:nodes, :links, :income_total, :outflow_total, :leftover_total)
    expect(payload[:next_step]).to include(:title, :primary_label, :primary_path)
  end
end
