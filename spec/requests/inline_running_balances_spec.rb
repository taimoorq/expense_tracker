require "rails_helper"

RSpec.describe "Inline running balances", type: :request do
  let(:user) { create(:user) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 9, 1)) }
  let(:account) { create(:account, user: user, kind: :checking) }
  let!(:entry) { create(:expense_entry, budget_month: month, source_account: account, occurred_on: month.month_on + 2.days, planned_amount: 1200) }

  before do
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000)
    sign_in user
  end

  it "renders an optional balance column in the existing regular table with its filters and actions" do
    get budget_month_path(month)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    table = html.at_css("#entries_table table")
    expect(table.css("thead th").map(&:text).map(&:strip)).to eq([ "Date", "Payee", "Status", "Amount", "Actions", "Balance after" ])
    expect(table.at_css("[data-balance-column-target='column']")['class']).to include("hidden")
    expect(table.at_css("#expense_entry_#{entry.id} [data-running-balance]").text).to include("-$200.00")
    expect(html.at_css("[data-balance-column-target='button']").text).to include("Show balances")
    expect(html.at_css("[data-expense-entries-filter-target='account']")).to be_present
    expect(table.at_css("a[aria-label='Edit entry']")).to be_present
    expect(response.body).not_to include("Adjust payment dates", "Account ledger", "Report opening balance")
  end

  it "recalculates the inline balances when the usual editor saves through Turbo" do
    patch budget_month_expense_entry_path(month, entry),
      params: { timeline_view: "full-list", expense_entry: { planned_amount: "800" } },
      headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    timeline = html.at_css("turbo-stream[target='timeline_section']")
    expect(timeline.at_css("[data-running-balance]").text).to include("$200.00")
    expect(timeline.at_css("[data-controller='balance-column']")).to be_present
  end

  it "keeps closed months on their existing frozen-evidence workflow" do
    result = Platform::TargetBackfill::Runner.call(user: user)
    result.workspace.update!(target_reads_enabled: true, target_writes_enabled: true)
    post budget_month_month_close_path(month)
    get budget_month_path(month)
    expect(response.body).to include("This month is closed")
    expect(response.body).not_to include("Show balances", "data-running-balance")
  end

  it "does not reveal balances from another user's month" do
    other_month = create(:budget_month)
    get budget_month_path(other_month)
    expect(response).to have_http_status(:not_found)
    expect(Nokogiri::HTML(response.body).css("[data-running-balance]")).to be_empty
  end
end
