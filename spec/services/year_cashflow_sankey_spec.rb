require "rails_helper"

RSpec.describe YearCashflowSankey do
  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  it "builds a year-to-date cash flow payload from all months in the year" do
    user = create(:user)
    january = create(:budget_month, user:, month_on: Date.new(2026, 1, 1), label: "January 2026")
    march = create(:budget_month, user:, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:budget_month, user:, month_on: Date.new(2025, 12, 1), label: "December 2025")

    create(:expense_entry, user:, budget_month: january, section: :income, category: "Salary", payee: "Employer A", planned_amount: 4_000, status: :paid)
    create(:expense_entry, user:, budget_month: january, section: :fixed, category: "Housing", payee: "Landlord", planned_amount: 1_500, status: :planned)
    create(:expense_entry, user:, budget_month: march, section: :income, category: "Side Work", payee: "Contract Work", planned_amount: 1_250, status: :paid)
    create(:expense_entry, user:, budget_month: march, section: :variable, category: "Groceries", payee: "Market", planned_amount: 320, status: :planned)

    payload = described_class.cached_payload(user:, year: 2026)

    expect(payload[:year]).to eq(2026)
    expect(payload[:month_count]).to eq(2)
    expect(payload[:income_total]).to eq(5_250.0)
    expect(payload[:outflow_total]).to eq(1_820.0)
    expect(payload[:leftover_total]).to eq(3_430.0)
    expect(payload[:nodes]).to include(include(name: "Employer A"), include(name: "Contract Work"), include(name: "2026 Income"), include(name: "Housing"), include(name: "Groceries"), include(name: "2026 Leftover"))
    expect(payload[:links]).to include(
      include(source: "Employer A", target: "2026 Income", value: 4_000.0),
      include(source: "Contract Work", target: "2026 Income", value: 1_250.0),
      include(source: "2026 Income", target: "Housing", value: 1_500.0),
      include(source: "2026 Income", target: "Groceries", value: 320.0),
      include(source: "2026 Income", target: "2026 Leftover", value: 3_430.0)
    )
  end

  it "refreshes the cached payload when a current-year entry changes" do
    user = create(:user)
    month = create(:budget_month, user:, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, user:, budget_month: month, section: :income, payee: "Employer A", planned_amount: 2_000, status: :paid)

    initial_payload = described_class.cached_payload(user:, year: Date.current.year)
    create(:expense_entry, user:, budget_month: month, section: :fixed, category: "Housing", planned_amount: 900, status: :planned)

    refreshed_payload = described_class.cached_payload(user:, year: Date.current.year)

    expect(initial_payload[:outflow_total]).to eq(0.0)
    expect(refreshed_payload[:outflow_total]).to eq(900.0)
    expect(refreshed_payload[:links]).to include(include(source: "#{Date.current.year} Income", target: "Housing", value: 900.0))
  end
end
