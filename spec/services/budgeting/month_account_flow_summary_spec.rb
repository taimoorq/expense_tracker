require "rails_helper"

RSpec.describe Budgeting::MonthAccountFlowSummary do
  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  it "builds charged and paid totals per account for the month" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    checking = create(:account, user: user, name: "Checking")
    visa = create(:account, user: user, name: "Visa")
    visa_card = create(:credit_card, user: user, name: "Visa Card", linked_account: visa, payment_account: checking, minimum_payment: 150, due_day: 20)

    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Main Job", planned_amount: 3200, source_account: checking)
    create(:expense_entry, budget_month: budget_month, user: user, section: :fixed, category: "Housing", payee: "Rent", planned_amount: 1200, source_account: checking)
    create(:expense_entry, budget_month: budget_month, user: user, section: :variable, category: "Streaming", payee: "Netflix", planned_amount: 25, source_account: visa)
    create(:expense_entry,
      budget_month: budget_month,
      user: user,
      section: :debt,
      category: "Credit Card",
      payee: visa_card.name,
      planned_amount: 300,
      source_account: checking,
      source_file: CreditCard.template_source_file,
      source_template: visa_card)
    create(:expense_entry, budget_month: budget_month, user: user, section: :manual, category: "Misc", payee: "Cash", planned_amount: 40, account: nil)

    payload = described_class.new(budget_month: budget_month).payload

    expect(payload[:labels]).to eq([ "Checking", "Visa" ])
    expect(payload[:charged_values]).to eq([ 1200.0, 25.0 ])
    expect(payload[:paid_values]).to eq([ 3200.0, 300.0 ])
    expect(payload[:charged_total]).to eq(1225.0)
    expect(payload[:paid_total]).to eq(3500.0)
    expect(payload[:account_count]).to eq(2)
    expect(payload[:tracked_entries_count]).to eq(4)
    expect(payload[:untracked_entries_count]).to eq(1)
    expect(payload[:top_account]).to include(name: "Checking", charged_total: 1200.0, paid_total: 3200.0)
  end

  it "caches payloads until month entries change" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    checking = create(:account, user: user, name: "Checking")

    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Main Job", planned_amount: 3000, source_account: checking)

    first_payload = described_class.cached_payload(budget_month: budget_month)

    create(:expense_entry, budget_month: budget_month, user: user, section: :fixed, payee: "Rent", planned_amount: 1200, source_account: checking)

    second_payload = described_class.cached_payload(budget_month: budget_month)

    expect(first_payload[:charged_total]).to eq(0.0)
    expect(second_payload[:charged_total]).to eq(1200.0)
  end
end
