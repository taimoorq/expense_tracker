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
    expect(payload[:financial_rhythm]).to eq("steady_income")
    expect(payload[:account_flow_months_included]).to eq(1)
    expect(payload[:account_flow_month_range_label]).to eq(month.label)
    expect(payload[:account_flow_payload]).to include(:labels, :charged_total, :paid_total)
    expect(payload[:year_cashflow_payload]).to include(:nodes, :links, :income_total, :outflow_total, :leftover_total)
    expect(payload[:next_step]).to include(:title, :primary_label, :primary_path)
  end

  it "keeps Home attention counts on target facts after read cutover" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      occurred_on: Date.current,
      category: "Utilities",
      payee: "Power",
      planned_amount: 100,
      status: :planned
    )
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    first = described_class.new(user: user, today: Date.current).call
    entry.update_columns(status: ExpenseEntry.statuses.fetch("paid"), actual_amount: 100)
    second = described_class.new(user: user.reload, today: Date.current).call

    expect(first).to include(due_planned_count: 1, review_attention_count: 1)
    expect(second).to include(due_planned_count: 1, review_attention_count: 1)
  end
end
