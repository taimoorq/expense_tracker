require "rails_helper"

RSpec.describe Accounts::EntryRunningBalances do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user, kind: :checking) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 9, 1)) }

  def entry(day, amount, **options)
    create(:expense_entry, user: user, budget_month: month, source_account: account,
      occurred_on: month.month_on + (day - 1), planned_amount: amount, **options)
  end

  def balances(selected_month = month, rows: selected_month.expense_entries.chronological)
    described_class.call(budget_month: selected_month.reload, entries: rows)
  end

  def enable_target
    result = Platform::TargetBackfill::Runner.call(user: user)
    expect(result).to be_success, result.as_json.inspect
    result.workspace.tap { |workspace| workspace.update!(target_writes_enabled: true, target_reads_enabled: true) }
  end

  [ false, true ].each do |target|
    context(target ? "target workspace" : "legacy workspace") do
      before { create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000) }

      it "uses actual paid amounts and planned unpaid amounts, carrying the result into later months" do
        paid = entry(2, 300, actual_amount: 200, status: :paid)
        planned = entry(5, 1000)
        income = entry(10, 1500, section: :income, category: "Salary")
        later_month = create(:budget_month, user: user, month_on: Date.new(2026, 11, 1))
        later = create(:expense_entry, user: user, budget_month: later_month, source_account: account, planned_amount: 50)
        enable_target if target
        planned.reload.update!(actual_amount: 0)

        expect(balances.values_at(paid.id, planned.id, income.id).map(&:amount)).to eq([ 800, -200, 1300 ])
        expect(balances(later_month).fetch(later.id).amount).to eq(1250)
      end

      it "preserves regular same-day entry order and ignores skipped amounts" do
        income = entry(5, 500, section: :income, category: "Salary")
        bill = entry(5, 200)
        skipped = entry(5, 900, status: :skipped)
        enable_target if target

        expect(balances.values_at(income.id, bill.id, skipped.id).map(&:amount)).to eq([ 1500, 1300, 1300 ])
      end

      it "counts matched activity once, plus activity without a budget row" do
        paid = entry(5, 125, actual_amount: 100, status: :paid)
        plan = entry(7, 50)
        import = create(:account_activity_import, account: account, started_on: month.month_on, ended_on: month.month_on.end_of_month)
        create(:account_activity, account: account, account_activity_import: import, transaction_on: Date.new(2026, 9, 5), expense_entry: paid, account_delta: -100, amount: 100)
        create(:account_activity, account: account, account_activity_import: import, transaction_on: Date.new(2026, 9, 6), row_number: 3, account_delta: -25, amount: 25)
        enable_target if target

        expect(balances.fetch(paid.id).amount).to eq(900)
        expect(balances.fetch(plan.id).amount).to eq(825)
        expect(balances(rows: [ plan ]).fetch(plan.id).amount).to eq(825)
      end

      it "keeps account balances independent and includes incoming transfers" do
        savings = create(:account, user: user, kind: :savings)
        create(:account_snapshot, account: savings, recorded_on: month.month_on.prev_day, balance: 100)
        transfer = entry(2, 200, destination_account: savings, category: "Savings transfer")
        withdrawal = entry(3, 50, source_account: savings)
        enable_target if target

        expect(balances.fetch(transfer.id).amount).to eq(800)
        expect(balances.fetch(withdrawal.id).amount).to eq(250)
      end

      it "resets the forecast at a report without adding covered actuals or older plans" do
        paid = entry(5, 100, actual_amount: 100, status: :paid)
        entry(5, 50)
        create(:account_snapshot, account: account, recorded_on: Date.new(2026, 9, 5), balance: 700)
        later = entry(6, 20, actual_amount: 20, status: :paid)
        enable_target if target

        expect(balances.fetch(paid.id).amount).to eq(900)
        expect(balances.fetch(later.id).amount).to eq(680)
        expect(balances.fetch(later.id).reported_on).to eq(Date.new(2026, 9, 5))
      end

      it "starts from a reported 200 opening balance instead of rolling older planned income forward" do
        prior_month = create(:budget_month, user: user, month_on: month.month_on.prev_month)
        create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 28), balance: 1055.26)
        create(:expense_entry, budget_month: prior_month, source_account: account, section: :income,
          category: "Salary", planned_amount: 1451)
        opening = account.account_snapshots.find_by!(recorded_on: month.month_on.prev_day)
        expect(Accounts::SnapshotWriter.update(snapshot: opening,
          attributes: { balance_date: "2026-09-01", balance_timing: "opening", balance: 200 })).to be(true)
        paycheck = entry(1, 2600, actual_amount: 2600, section: :income, category: "Salary", status: :paid)
        bill = entry(1, 107.41, actual_amount: 107.41, status: :paid)
        enable_target if target

        expect(balances.fetch(paycheck.id).amount).to eq(2800)
        expect(balances.fetch(bill.id).amount).to eq(2692.59.to_d)
        expect(balances.fetch(paycheck.id).reported_on).to eq(Date.new(2026, 8, 31))
      end

      it "uses a newer manual report than an older institution report" do
        create(:account_activity_import, account: account, metadata: { institution_balance: "200", institution_balance_as_of: "2026-09-01" })
        create(:account_snapshot, account: account, recorded_on: Date.new(2026, 9, 5), balance: 1000)
        later = entry(6, 20)
        enable_target if target

        expect(balances.fetch(later.id).amount).to eq(980)
      end

      it "keeps a zero actual payment zero" do
        paid = entry(2, 200)
        enable_target if target
        paid.reload.update!(actual_amount: 0, status: :paid)
        expect(balances.fetch(paid.id).amount).to eq(1000)
      end
    end
  end

  it "leaves unlinked, undated and unanchored balances unavailable" do
    unanchored = entry(2, 200)
    unlinked = entry(3, 100, source_account: nil)
    undated = entry(4, 50, occurred_on: nil)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 9, 10), balance: 1000)
    expect(balances.values.map(&:amount)).to eq([ nil, nil, nil ])
    expect(balances.fetch(unlinked.id).message).to include("Link this entry")
    expect(balances.fetch(undated.id).message).to include("Add a date")
    expect(balances.fetch(unanchored.id).message).to include("before this date")
  end

  it "uses actual movement dates for matched entries" do
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000)
    paid = entry(2, 100, actual_amount: 100, status: :paid)
    import = create(:account_activity_import, account: account)
    create(:account_activity, account: account, account_activity_import: import, transaction_on: Date.new(2026, 9, 6), expense_entry: paid, account_delta: -100)
    expect(balances.fetch(paid.id).effective_on).to eq(Date.new(2026, 9, 6))
    expect(balances.fetch(paid.id).amount).to eq(900)
  end

  it "does not invent a balance for an unmatched paid row covered by imports" do
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000)
    paid = entry(2, 100, actual_amount: 100, status: :paid)
    create(:account_activity_import, account: account, started_on: month.month_on, ended_on: month.month_on.end_of_month)
    expect(balances.fetch(paid.id).amount).to be_nil
  end

  it "uses posted allocations plus only the remaining target plan" do
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000)
    plan = entry(5, 100)
    workspace = enable_target
    item = workspace.budget_items.sole
    transaction = workspace.financial_transactions.create!(effective_on: Date.new(2026, 9, 4), description: "Partial payment", gross_amount: 40,
      currency_code: "USD", flow_kind: "outflow", state: "posted", origin_kind: "manual")
    workspace.account_postings.create!(financial_transaction: transaction, account: account, amount: -40, currency_code: "USD", role: "primary", sequence_number: 0)
    workspace.budget_allocations.create!(financial_transaction: transaction, budget_item: item, amount: 40, currency_code: "USD", match_kind: "manual", matched_at: Time.current)
    expect(balances.fetch(plan.id).amount).to eq(900)
    expect(balances.fetch(plan.id).effective_on).to eq(Date.new(2026, 9, 5))
    transaction.update!(state: "reversed")
    expect(balances.fetch(plan.id).amount).to eq(900)
  end

  it "does not load movement one query per row" do
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000)
    entry(2, 10)
    small = count_select_queries { balances }
    30.times { |index| entry((index % 28) + 1, 10) }
    expect(count_select_queries { balances }).to be <= small
  end

  Account.kinds.keys.each do |kind|
    it "supports signed balances for #{kind}" do
      account.update!(kind: kind)
      opening = account.liability? ? -1000 : 1000
      create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: opening)
      payment = entry(5, 100)
      expect(balances.fetch(payment.id).amount).to eq(opening - 100)
    end
  end
end
