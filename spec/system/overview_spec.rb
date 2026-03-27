require "rails_helper"

RSpec.describe "Overview", type: :system do
  it "shows workflow widgets and opens targeted month tabs" do
    user = create(:user, email: "overviewwidgets@example.com")
    current_month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry,
      budget_month: current_month,
      user: user,
      occurred_on: Date.current,
      section: :fixed,
      category: "Utilities",
      payee: "Power Company",
      planned_amount: 95,
      status: :planned)
    create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8)
    account = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: account, recorded_on: Date.current, balance: 2200)

    sign_in_as(user)
    visit root_path

    expect(page).to have_content("Continue")
    expect(page).to have_content("How this is chosen")
    expect(page).to have_content("Attention Queue")
    expect(page).to have_content("Planning Templates")
    expect(page).to have_content("Accounts Snapshot")
    expect(page).to have_content("Quick Actions")
    expect(page).to have_content("Set up the month in the right order")
    expect(page).to have_link("Set Up Templates")
    expect(page).to have_content("Adjust as the month unfolds")
    expect(page).to have_content("Done")

    all(:link, "Open Plan and Edit").first.click

    expect(page).to have_current_path(budget_month_path(current_month, tab: "entries"), ignore_query: false)
    expect(page).to have_content("Plan and Edit This Month")
  end

  it "shows a setup-focused overview when no months exist" do
    user = create(:user, email: "overviewempty@example.com")

    sign_in_as(user)
    visit root_path

    expect(page).to have_content("No active month yet")
    expect(page).to have_content("Add your first account")
    expect(page).to have_link("Set up Accounts")
    expect(page).to have_link("Create Account")
    expect(page).to have_content("Set up the month in the right order")
    expect(page).to have_content("Next")
  end
end
