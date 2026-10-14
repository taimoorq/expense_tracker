require "rails_helper"

RSpec.describe ExpenseEntries::ValueOptions do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1)) }
  subject(:options) { described_class.new(user: user, budget_month: budget_month) }

  it "offers distinct values across the user's months without including another user's data" do
    earlier_month = create(:budget_month, user: user, month_on: Date.new(2026, 2, 1))
    create(:expense_entry, budget_month: earlier_month, payee: "Pepco", category: "Utilities")
    create(:expense_entry, budget_month: budget_month, payee: " pepco ", category: " utilities ")
    create(:expense_entry, budget_month: budget_month, payee: " ", category: nil)
    create(:expense_entry, payee: "Private payee", category: "Private category")

    expect(options.payees.map(&:downcase)).to eq([ "pepco" ])
    expect(options.categories.map(&:downcase)).to eq([ "utilities" ])
  end

  it "includes saved recurring names and workspace categories and ledger payees" do
    workspace = create(:budget_workspace, legacy_owner_user: user)
    budget_month.update!(budget_workspace: workspace)
    create(:subscription, user: user, name: "Netflix")
    create(:category, budget_workspace: workspace, name: "Streaming")
    create(:category, budget_workspace: workspace, name: "Archived", archived_at: Time.current)
    create(:planning_template, budget_workspace: workspace, name: "Rent")
    create(:budget_item, budget_workspace: workspace, payee_snapshot: "Landlord")
    create(:financial_transaction, budget_workspace: workspace, payee: "Corner Store")
    create(:category, name: "Private category")
    create(:financial_transaction, payee: "Private payee")

    expect(options.categories).to eq([ "Streaming" ])
    expect(options.payees).to eq([ "Corner Store", "Landlord", "Netflix", "Rent" ])
  end

  it "reuses existing spelling for case and surrounding-space differences" do
    create(:expense_entry, budget_month: budget_month, payee: "Pepco", category: "Utilities")

    expect(options.normalize(payee: " pepco ", category: " UTILITIES ", planned_amount: "50")).to eq(
      payee: "Pepco", category: "Utilities", planned_amount: "50"
    )
  end

  it "keeps genuinely new values and does not silently replace a nearby spelling" do
    create(:expense_entry, budget_month: budget_month, payee: "Pepco", category: "Utilities")

    expect(options.normalize(payee: " Pepxo ", category: " Garden ")).to eq(payee: "Pepxo", category: "Garden")
    expect(options.normalize(status: "paid")).to eq(status: "paid")
  end
end
