require "rails_helper"

RSpec.describe "Full List ledger layout", type: :request do
  let(:user) { create(:user) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 9, 1)) }
  let(:account) { create(:account, user: user, name: "Everyday Checking") }

  before { sign_in user }

  def row_for(entry)
    Nokogiri::HTML(response.body).at_css("#entries_table #expense_entry_#{entry.id}")
  end

  it "stacks payee details and uses the signed paid amount with its planned comparison" do
    entry = create(:expense_entry, budget_month: month, source_account: account, payee: "Card payment",
      category: "Credit card", section: :debt, planned_amount: 2897.38, actual_amount: 2000, status: :paid)
    get budget_month_path(month)
    row = row_for(entry)
    expect(row.at_css("time")['datetime']).to eq("2026-09-01")
    expect(row.at_css(".ta-full-list-date").text).to include("Sep 1", "Tue")
    expect(row.at_css(".ta-full-list-payee").text).to include("Card payment", "Credit card · Debt · Everyday Checking")
    expect(row.at_css("[data-full-list-amount]").text).to include("−$2,000.00", "Planned $2,897.38")
    expect(row['data-reason']).to eq("Credit card")
    expect(row['data-value']).to eq("credit card")
    expect(row['data-account']).to eq("Everyday Checking")
    expect(row['data-status']).to eq("paid")
    expect(row.at_css("button[aria-label='Record payment']")).to be_nil
    expect(row.at_css("a[aria-label='Edit entry']")['data-turbo-frame']).to eq("entry_editor_modal")
  end

  it "distinguishes planned, skipped, zero and missing actual amounts" do
    planned = create(:expense_entry, budget_month: month, planned_amount: 200, actual_amount: 0, section: :income)
    skipped = create(:expense_entry, budget_month: month, planned_amount: 50, status: :skipped)
    zero = create(:expense_entry, budget_month: month, planned_amount: 25, actual_amount: 0, status: :paid)
    unknown = create(:expense_entry, budget_month: month, planned_amount: 75, actual_amount: nil, status: :paid, occurred_on: nil, payee: nil)
    get budget_month_path(month)
    expect(row_for(planned).at_css("[data-full-list-amount]").text.strip).to eq("+$200.00")
    expect(row_for(skipped).at_css("[data-full-list-amount]").text).to include("$0.00", "Planned $50.00")
    expect(row_for(zero).at_css("[data-full-list-amount]").text).to include("$0.00", "Planned $25.00")
    expect(row_for(unknown).text).to include("No date", "No payee", "Actual not recorded", "Planned $75.00")
  end

  it "keeps sorting available in Grouped while Full List is chronological" do
    create(:expense_entry, budget_month: month)
    get budget_month_path(month)
    expect(Nokogiri::HTML(response.body).css("#entries_table [data-controller='sortable-table']")).to be_empty
    get budget_month_path(month), params: { view: "sections" }
    expect(Nokogiri::HTML(response.body).css("#timeline_section [data-controller='sortable-table']")).not_to be_empty
  end
end
