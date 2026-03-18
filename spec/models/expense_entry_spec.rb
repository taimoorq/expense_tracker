require "rails_helper"

RSpec.describe ExpenseEntry, type: :model do
  it "links source_account from the account name when available" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    entry = create(:expense_entry, budget_month: month, user: user, account: "Checking")

    expect(entry.source_account).to eq(account)
  end

  it "prefers the template linked account over the account string" do
    user = create(:user)
    linked_account = create(:account, user: user, name: "Primary Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    schedule = create(:pay_schedule,
                      user: user,
                      name: "Payroll",
                      cadence: :monthly,
                      amount: 2500,
                      first_pay_on: Date.new(2026, 3, 15),
                      day_of_month_one: 15,
                      linked_account: linked_account)

    entry = create(:expense_entry,
                   budget_month: month,
                   user: user,
                   source_template: schedule,
                   account: "Outdated Label",
                   section: :income,
                   status: :paid)

    expect(entry.source_account).to eq(linked_account)
  end

  it "prefers linked source_account name for display" do
    user = create(:user)
    linked_account = create(:account, user: user, name: "Primary Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    entry = create(:expense_entry,
                   budget_month: month,
                   user: user,
                   source_account: linked_account,
                   account: "Legacy Label")

    expect(entry.account_name).to eq("Primary Checking")
  end
end
