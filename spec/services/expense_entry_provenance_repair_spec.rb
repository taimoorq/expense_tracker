require "rails_helper"

RSpec.describe ExpenseEntryProvenanceRepair do
  it "links imported recurring entries back to their template and canonical account" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    subscription = create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8, linked_account: checking, account: "Legacy Checking")
    entry = create(:expense_entry,
                   budget_month: month,
                   user: user,
                   payee: "Netflix",
                   section: :fixed,
                   source_file: "subscription",
                   source_template: nil,
                   source_account: nil,
                   account: "Old Label")

    described_class.new(entry: entry).repair!

    expect(entry.reload.source_template).to eq(subscription)
    expect(entry.source_account).to eq(checking)
    expect(entry.account).to eq("Checking")
  end
end
