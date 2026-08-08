require "rails_helper"

RSpec.describe Accounts::TargetBalanceResolver do
  it "matches legacy snapshot, paid, and planned balance semantics exactly" do
    user = create(:user)
    account = create(:account, user: user, kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1))
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 7, 3),
      section: :income,
      planned_amount: 200,
      actual_amount: 200,
      status: :paid
    )
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 7, 6),
      section: :fixed,
      planned_amount: 75,
      status: :planned
    )
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace

    legacy = Accounts::BalanceResolver.new(account: account, as_of: Date.new(2026, 7, 5)).call
    target = described_class.new(account: account.reload, as_of: Date.new(2026, 7, 5)).call

    expect(target).to have_attributes(
      balance_source: :snapshot,
      base_balance: legacy.base_balance,
      paid_delta: legacy.paid_delta,
      planned_delta: legacy.planned_delta,
      current_balance: legacy.current_balance,
      projected_balance: legacy.projected_balance,
      paid_entries_count: legacy.paid_entries_count,
      planned_entries_count: legacy.planned_entries_count
    )
    expect(workspace.balance_observations.count).to eq(1)
  end

  it "rolls an institution balance forward with canonical imported postings" do
    user = create(:user)
    account = create(:account, user: user, kind: :checking)
    import = create(
      :account_activity_import,
      user: user,
      account: account,
      metadata: { institution_balance: "2200.00", institution_balance_as_of: "2026-07-02" },
      started_on: Date.new(2026, 7, 1),
      ended_on: Date.new(2026, 7, 31)
    )
    create(
      :account_activity,
      user: user,
      account: account,
      account_activity_import: import,
      transaction_on: Date.new(2026, 7, 3),
      amount: 25,
      account_delta: -25
    )
    Platform::TargetBackfill::Runner.call(user: user)

    target = described_class.new(account: account.reload, as_of: Date.new(2026, 7, 5)).call

    expect(target).to have_attributes(
      balance_source: :institution_import,
      base_balance: 2_200.to_d,
      paid_delta: -25.to_d,
      current_balance: 2_175.to_d,
      activity_through_on: Date.new(2026, 7, 3)
    )
  end
end
