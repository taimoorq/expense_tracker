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

  it "uses one target bundle for posted movement and remaining plans after read cutover" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    visa = create(:account, user: user, name: "Visa", kind: :credit_card)
    january = create(:budget_month, user: user, month_on: Date.new(2026, 1, 1), label: "January 2026")
    february = create(:budget_month, user: user, month_on: Date.new(2026, 2, 1), label: "February 2026")
    create(:expense_entry, budget_month: january, user: user, section: :income, payee: "Employer", planned_amount: 1_900, actual_amount: 2_000, status: :paid, source_account: checking)
    create(:expense_entry, budget_month: january, user: user, section: :fixed, payee: "Rent", planned_amount: 550, actual_amount: 600, status: :paid, source_account: checking)
    create(:expense_entry, budget_month: february, user: user, section: :variable, payee: "Market", planned_amount: 80, actual_amount: 100, status: :paid, source_account: visa)
    create(:expense_entry, budget_month: february, user: user, section: :debt, payee: "Visa payment", planned_amount: 250, status: :planned, source_account: checking, destination_account: visa)
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    payload = described_class.new(user: user, month_window: "all").call

    expect(payload[:account_flow_calculation_version]).to eq("target-v1")
    expect(payload[:account_flow_payload]).to include(
      labels: [ "Checking", "Visa" ],
      charged_values: [ 600.0, 100.0 ],
      paid_values: [ 2_000.0, 0.0 ],
      charged_total: 700.to_d,
      paid_total: 2_000.to_d,
      tracked_entries_count: 3
    )
    expect(payload[:account_movement_payload]).to include(month_labels: [ "Jan 2026", "Feb 2026" ])
    expect(payload[:account_movement_payload][:credit_card]).to include(
      added_total: 100.0,
      paid_total: 0.0,
      planned_payment_total: 250.0
    )
    expect(payload[:account_movement_payload][:bank_accounts]).to include(
      money_in_total: 2_000.0,
      paid_out_total: 600.0,
      left_to_pay_total: 250.0
    )
  end

  it "keeps target movement queries bounded as account and month counts grow" do
    user = create(:user)
    accounts = create_list(:account, 8, user: user, kind: :checking)
    6.times do |index|
      month_on = Date.new(2026, 1, 1).next_month(index)
      month = create(:budget_month, user: user, month_on: month_on, label: month_on.strftime("%B %Y"))
      accounts.each do |account|
        create(:expense_entry, budget_month: month, user: user, occurred_on: month_on, source_account: account, planned_amount: 25)
      end
    end
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    queries = count_select_queries { described_class.new(user: user.reload, month_window: "all").call }

    expect(queries).to be <= 15
  end
end
