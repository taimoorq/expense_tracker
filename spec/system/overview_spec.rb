require "rails_helper"

RSpec.describe "Overview", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  it "shows workflow widgets and opens targeted month tabs" do
    user = create(:user, email: "overviewwidgets@example.com")
    current_month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry,
      budget_month: current_month,
      user: user,
      section: :income,
      category: "Paycheck",
      payee: "Employer A",
      planned_amount: 3_200,
      status: :paid)
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
    expect(page).to have_content("Recurring")
    expect(page).to have_content("Accounts Snapshot")
    expect(page).to have_content("Account Movement")
    expect(page).to have_content("Quick Actions")
    expect(page).to have_content("Set up the month in the right order")
    expect(page).to have_content("Weekly check-in")
    expect(page).to have_content("Due next 7 days")
    expect(page).to have_content("Mostly fixed paycheck")
    expect(page).to have_content("#{Date.current.year} money flow")
    expect(page).to have_content("Loading the #{Date.current.year} cash flow graph")
    expect(page).to have_link("Set Up Recurring")
    expect(page).to have_content("Adjust as the month unfolds")
    expect(page).to have_content("Done")

    all(:link, "Open Plan and Edit").first.click

    expect(page).to have_current_path(budget_month_tab_path(current_month, "entries"), ignore_query: false)
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
    expect(page).to have_content("First useful step")
    expect(page).to have_content("Start small, then build from there")
    expect(page).to have_content("No #{Date.current.year} cash flow to chart yet")
    expect(page).to have_content("Next")
  end

  it "shows calm completion copy when the current month has no attention items" do
    user = create(:user, email: "overviewclear@example.com")
    current_month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    account = create(:account, user: user, name: "Checking", kind: :checking)
    create(:expense_entry,
      budget_month: current_month,
      user: user,
      source_account: account,
      occurred_on: Date.current,
      section: :income,
      category: "Paycheck",
      payee: "Employer",
      planned_amount: 3_000,
      actual_amount: 3_000,
      status: :paid)

    sign_in_as(user)
    visit root_path

    expect(page).to have_content("Small win")
    expect(page).to have_content("Nothing needs cleanup right now.")
    expect(page).to have_content("On track")
  end

  it "filters account activity by selected saved months", js: true do
    user = create(:user, email: "overviewaccountflow@example.com")
    current_month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    previous_month = create(:budget_month, user: user, month_on: Date.current.prev_month.beginning_of_month, label: Date.current.prev_month.strftime("%B %Y"))
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    visa = create(:account, user: user, name: "Visa", kind: :credit_card)

    create(:expense_entry, budget_month: current_month, user: user, section: :income, payee: "Employer", planned_amount: 3_000, source_account: checking)
    create(:expense_entry, budget_month: previous_month, user: user, section: :variable, payee: "Streaming", planned_amount: 45, source_account: visa)

    sign_in_as(user)
    visit root_path

    expect(page).to have_content("2 months included")
    expect(page).to have_content("#{previous_month.label} to #{current_month.label}")
    expect(page).to have_content("Top activity: Checking")

    within("turbo-frame#overview_account_flow") do
      select "Last month", from: "overview-account-flow-months"
      click_button "Apply"
    end

    expect(page).to have_css("turbo-frame#overview_account_flow", text: "1 month included")
    expect(page).to have_css("turbo-frame#overview_account_flow", text: current_month.label)
    expect(page).to have_no_css("turbo-frame#overview_account_flow", text: "#{previous_month.label} to #{current_month.label}")
  end

  it "lets users review card movement totals and continue to card payoff progress", js: true do
    travel_to Time.zone.local(2026, 6, 15, 12, 0, 0) do
      user = create(:user, email: "overviewcardmovement@example.com")
      month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
      checking = create(:account, user: user, name: "Checking", kind: :checking)
      card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
      create(:account_snapshot, account: card, recorded_on: Date.new(2026, 6, 1), balance: -1_000)

      create(:expense_entry,
        budget_month: month,
        user: user,
        source_account: card,
        occurred_on: Date.new(2026, 6, 10),
        section: :variable,
        status: :paid,
        actual_amount: 120,
        payee: "Market")

      create(:expense_entry,
        budget_month: month,
        user: user,
        source_account: checking,
        destination_account: card,
        occurred_on: Date.new(2026, 6, 15),
        section: :debt,
        status: :paid,
        actual_amount: 300,
        payee: "Rewards Visa")

      sign_in_as(user)
      visit root_path

      expect(page).to have_content("Added vs paid off by month")
      expect(page).to have_content("$120.00")
      expect(page).to have_content("$300.00")

      find("summary", text: "Review card movement entries").click
      within("details", text: "Review card movement entries") do
        click_link "June 2026 · Rewards Visa · Paid off"
      end

      expect(page).to have_current_path(budget_month_account_movement_path(month, account_id: card.id, movement_type: "credit_card_paid"), ignore_query: false)
      expect(page).to have_content("Credit card payments made")
      expect(page).to have_content("Checking")
      expect(page).to have_content("Rewards Visa")
      expect(page).to have_content("$300.00")

      click_link "Open Account"

      expect(page).to have_current_path(account_path(card), ignore_query: false)
      expect(page).to have_content("Credit card payoff progress")
      expect(page).to have_text(/paid down this month/i)
      expect(page).to have_content("$300.00")
      expect(page).to have_text(/added this month/i)
      expect(page).to have_content("$120.00")
      expect(page).to have_content("$820.00 remains")
      expect(page).to have_content("18%")
    end
  end
end
