require "rails_helper"

RSpec.describe ExpenseEntry, type: :model do
  describe "financial invariants" do
    it "rejects a date outside the entry's budget month" do
      budget_month = create(:budget_month, month_on: Date.new(2026, 3, 1), label: "March 2026")
      entry = build(:expense_entry, budget_month: budget_month, occurred_on: Date.new(2026, 4, 1))

      expect(entry).not_to be_valid
      expect(entry.errors.full_messages).to include("Date must be in March 2026 (March 1 through March 31)")
    end

    it "allows an exact pay-schedule date adjusted across a month boundary" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 2, 1), label: "February 2026")
      schedule = create(
        :pay_schedule,
        user: user,
        cadence: :monthly,
        first_pay_on: Date.new(2026, 2, 1),
        day_of_month_one: 28,
        weekend_adjustment: :next_monday
      )
      entry = build(
        :expense_entry,
        user: user,
        budget_month: budget_month,
        occurred_on: Date.new(2026, 3, 2),
        source_file: schedule.template_source_file,
        source_template: schedule
      )

      expect(entry).to be_valid
    end

    it "rejects an account movement with the same source and destination" do
      user = create(:user)
      budget_month = create(:budget_month, user: user)
      checking = create(:account, user: user, kind: :checking)
      entry = build(:expense_entry, budget_month: budget_month, source_account: checking, destination_account: checking)

      expect(entry).not_to be_valid
      expect(entry.errors.full_messages).to include("Money goes to must be different from Money comes from")
    end
  end

  describe "amount semantics" do
    it "uses actual before planned but excludes skipped entries from financial contribution" do
      entry = build(:expense_entry, planned_amount: 100, actual_amount: 90, status: :paid)

      expect(entry.effective_amount.to_d).to eq(90.to_d)
      expect(entry.contributing_amount.to_d).to eq(90.to_d)

      entry.status = :skipped

      expect(entry.effective_amount.to_d).to eq(90.to_d)
      expect(entry.contributing_amount.to_d).to eq(0.to_d)
      expect(entry.cashflow_amount.to_d).to eq(0.to_d)
    end
  end

  it "links source_account from the account name when available" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    entry = create(:expense_entry, budget_month: month, user: user, account: "Checking")

    expect(entry.source_account).to eq(account)
  end

  it "defaults source_file to manual when blank" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    entry = create(:expense_entry, budget_month: month, user: user, source_file: nil)

    expect(entry.source_file).to eq("manual")
    expect(entry).to be_manual_origin
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
    expect(entry.account).to eq("Primary Checking")
  end

  it "prefers a credit card payment account over the account string" do
    user = create(:user)
    payment_account = create(:account, user: user, name: "House Checking")
    card_account = create(:account, user: user, name: "Rewards Visa")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    card = create(:credit_card,
                  user: user,
                  name: "Visa",
                  linked_account: card_account,
                  payment_account: payment_account,
                  account: "Old Label")

    entry = create(:expense_entry,
                   budget_month: month,
                   user: user,
                   source_template: card,
                   account: "Outdated Label",
                   section: :debt,
                   status: :planned)

    expect(entry.source_account).to eq(payment_account)
    expect(entry.account_name).to eq("House Checking")
    expect(entry.account).to eq("House Checking")
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
