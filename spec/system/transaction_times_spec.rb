require "rails_helper"

RSpec.describe "Transaction times", type: :system, js: true do
  it "orders the visible ledger and running balances by time while keeping assumed times hidden" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    account = create(:account, user: user, kind: :checking)
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 600)
    debit = create(:expense_entry, budget_month: month, source_account: account, occurred_on: Date.current, payee: "Untimed bill", planned_amount: 30)
    income = create(:expense_entry, budget_month: month, source_account: account, occurred_on: Date.current, section: :income, payee: "Untimed income", planned_amount: 100)
    late = create(:expense_entry, budget_month: month, source_account: account, occurred_on: Date.current, section: :income, payee: "Afternoon income", planned_amount: 200, transaction_time: "14:00")
    early = create(:expense_entry, budget_month: month, source_account: account, occurred_on: Date.current, payee: "Morning bill", planned_amount: 20, transaction_time: "09:15")
    sign_in_as(user)
    visit budget_month_path(month)
    expect(page).to have_css("[data-full-list-payee]", count: 4)
    expect(all("[data-full-list-payee]").map(&:text)).to eq([ income, early, late, debit ].map(&:payee))
    within("#timeline_section") do
      expect(page).to have_no_content("12:00 AM")
      expect(page).to have_no_content("23:59")
      click_button "Show balances"
    end
    within("#expense_entry_#{late.id}") { click_link "Edit entry" }
    # Chrome's segmented time control otherwise retains the previous PM segment.
    page.execute_script("arguments[0].value = '08:30:00'; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", find_field("Time"))
    expect(page).to have_field("Time", with: "08:30:00")
    click_button "Update Entry"
    expect(page).to have_content("Entry updated.")
    expect(ExpenseEntry.find(late.id).transaction_time).to eq("08:30:00")
    expect(page).to have_css("[data-full-list-payee]", count: 4)
    expect(all("[data-full-list-payee]").map(&:text)).to eq([ income, late, early, debit ].map(&:payee))
    within("#expense_entry_#{late.id}") { expect(page).to have_css("[data-running-balance]", text: "$900.00") }
  end
end
