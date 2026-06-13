require "rails_helper"

RSpec.describe Accounts::MonthlyMovementSummary do
  it "builds monthly credit card and bank account movement payloads" do
    user = create(:user)
    march = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    april = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    visa = create(:account, user: user, name: "Visa", kind: :credit_card)

    create(:expense_entry, budget_month: march, user: user, source_account: checking, section: :income, status: :paid, actual_amount: 3_000)
    create(:expense_entry, budget_month: march, user: user, source_account: checking, section: :fixed, status: :paid, actual_amount: 900)
    create(:expense_entry, budget_month: march, user: user, source_account: checking, section: :fixed, status: :planned, planned_amount: 250)
    create(:expense_entry, budget_month: march, user: user, source_account: visa, section: :variable, status: :paid, actual_amount: 125)
    create(:expense_entry, budget_month: march, user: user, source_account: checking, destination_account: visa, section: :debt, status: :paid, actual_amount: 300)

    create(:expense_entry, budget_month: april, user: user, source_account: checking, section: :income, status: :paid, actual_amount: 3_200)
    create(:expense_entry, budget_month: april, user: user, source_account: visa, section: :variable, status: :paid, actual_amount: 80)
    create(:expense_entry, budget_month: april, user: user, source_account: checking, destination_account: visa, section: :debt, status: :planned, planned_amount: 200)

    payload = described_class.new(budget_months: [ april, march ]).payload

    expect(payload[:month_labels]).to eq([ "Mar 2026", "Apr 2026" ])
    expect(payload[:credit_card][:added_total]).to eq(205.0)
    expect(payload[:credit_card][:paid_total]).to eq(300.0)
    expect(payload[:credit_card][:planned_payment_total]).to eq(200.0)
    expect(payload[:bank_accounts][:money_in_total]).to eq(6200.0)
    expect(payload[:bank_accounts][:paid_out_total]).to eq(1200.0)
    expect(payload[:bank_accounts][:left_to_pay_total]).to eq(450.0)

    expect(payload[:credit_card][:drilldowns]).to include(
      hash_including(
        movement_type: "credit_card_paid",
        account_id: visa.id,
        budget_month_id: march.id,
        amount: 300.0,
        entry_count: 1
      ),
      hash_including(
        movement_type: "credit_card_planned",
        account_id: visa.id,
        budget_month_id: april.id,
        amount: 200.0,
        entry_count: 1
      )
    )
    expect(payload[:bank_accounts][:drilldowns]).to include(
      hash_including(
        movement_type: "bank_paid_out",
        account_id: checking.id,
        budget_month_id: march.id,
        amount: 1_200.0,
        entry_count: 2
      )
    )
  end
end
