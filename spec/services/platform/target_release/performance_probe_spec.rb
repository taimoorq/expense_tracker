require "rails_helper"

RSpec.describe "target release performance evidence" do
  it "captures bounded runtime and PostgreSQL query-plan evidence without financial values" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    create(:account_snapshot, account: account, balance: 2_400, recorded_on: Date.current.prev_day)
    create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    runtime = Platform::TargetRelease::PerformanceProbe.call(workspace: workspace, samples: 1)
    plans = Platform::TargetRelease::QueryPlanProbe.call(workspace: workspace)

    expect(runtime.probes.reject(&:passed?).map(&:as_json)).to be_empty
    expect(runtime.probes.map(&:name)).to include("home", "reports", "accounts_summary", "account_detail")
    expect(runtime.probes).to all(satisfy { |probe| probe.p95_ms >= 0 && probe.max_select_count.positive? })
    expect(plans).to be_passed
    expect(plans.plans.map(&:name)).to contain_exactly(
      "latest_account_observations",
      "account_activity_timeline",
      "period_actual_totals",
      "report_category_totals",
      "unmatched_activity",
      "audit_timeline"
    )
    expect(plans.as_json.to_json).not_to include("2,400", "2400.0")
  end

  it "stays inside release budgets with five years, twelve accounts, and six thousand transactions" do
    user = create(:user)
    accounts = Array.new(12) { |index| create(:account, user: user, name: "Account #{index + 1}") }
    60.times do |index|
      month_on = Date.current.beginning_of_month.prev_month(59 - index)
      create(:budget_month, user: user, month_on: month_on, label: month_on.strftime("%B %Y"))
    end
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    categories = Array.new(10) do |index|
      workspace.categories.create!(
        name: "Category #{index + 1}",
        flow_kind: "outflow",
        budget_group: index.even? ? "fixed" : "variable",
        display_order: index
      )
    end
    add_production_shape_records(
      workspace: workspace,
      accounts: accounts,
      categories: categories
    )
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    runtime = Platform::TargetRelease::PerformanceProbe.call(workspace: workspace, samples: 3)
    plans = Platform::TargetRelease::QueryPlanProbe.call(workspace: workspace)

    expect(runtime.dataset_counts).to include(
      accounts: 12,
      periods: 60,
      items: 1_200,
      transactions: 6_000,
      postings: 6_000,
      allocations: 1_200,
      observations: 12
    )
    expect(runtime.probes.select { |probe| probe.max_select_count > probe.select_budget }.map(&:as_json)).to be_empty
    expect(plans.plans.reject(&:passed?).map(&:as_json)).to be_empty
  end

  def add_production_shape_records(workspace:, accounts:, categories:)
    timestamp = Time.current
    currency = workspace.default_currency_code
    periods = workspace.budget_periods.order(:starts_on).to_a
    insert_observations(workspace, accounts, periods.first.starts_on, timestamp, currency)

    item_rows = []
    transaction_rows = []
    posting_rows = []
    allocation_rows = []
    periods.each_with_index do |period, period_index|
      period_items = Array.new(20) do |item_index|
        item_id = SecureRandom.uuid
        item_rows << {
          id: item_id,
          budget_workspace_id: workspace.id,
          budget_period_id: period.id,
          category_id: categories[item_index % categories.size].id,
          intended_source_account_id: accounts[item_index % accounts.size].id,
          flow_kind: "outflow",
          budget_group: item_index.even? ? "fixed" : "variable",
          planned_amount: 25 + item_index,
          currency_code: currency,
          scheduled_on: period.starts_on + (item_index % 28).days,
          state: "open",
          origin_kind: "manual",
          name_snapshot: "Plan #{period_index}-#{item_index}",
          created_at: timestamp,
          updated_at: timestamp
        }
        item_id
      end

      100.times do |transaction_index|
        transaction_id = SecureRandom.uuid
        amount = 10 + (transaction_index % 90)
        transaction_rows << {
          id: transaction_id,
          budget_workspace_id: workspace.id,
          category_id: categories[transaction_index % categories.size].id,
          effective_on: period.starts_on + (transaction_index % 28).days,
          posted_on: period.starts_on + (transaction_index % 28).days,
          description: "Transaction #{period_index}-#{transaction_index}",
          gross_amount: amount,
          currency_code: currency,
          flow_kind: "outflow",
          state: "posted",
          origin_kind: "manual",
          created_at: timestamp,
          updated_at: timestamp
        }
        posting_rows << {
          id: SecureRandom.uuid,
          budget_workspace_id: workspace.id,
          financial_transaction_id: transaction_id,
          account_id: accounts[transaction_index % accounts.size].id,
          amount: -amount,
          currency_code: currency,
          role: "primary",
          sequence_number: 0,
          created_at: timestamp,
          updated_at: timestamp
        }
        next unless transaction_index < period_items.size

        allocation_rows << {
          id: SecureRandom.uuid,
          budget_workspace_id: workspace.id,
          budget_item_id: period_items.fetch(transaction_index),
          financial_transaction_id: transaction_id,
          matched_by_membership_id: workspace.workspace_memberships.first.id,
          amount: amount,
          currency_code: currency,
          match_kind: "manual",
          matched_at: timestamp,
          created_at: timestamp,
          updated_at: timestamp
        }
      end
    end

    insert_all_in_batches(BudgetItem, item_rows)
    insert_all_in_batches(FinancialTransaction, transaction_rows)
    insert_all_in_batches(AccountPosting, posting_rows)
    insert_all_in_batches(BudgetAllocation, allocation_rows)
  end

  def insert_observations(workspace, accounts, starts_on, timestamp, currency)
    rows = accounts.map.with_index do |account, index|
      {
        id: SecureRandom.uuid,
        budget_workspace_id: workspace.id,
        account_id: account.id,
        observed_at: timestamp,
        effective_through_at: starts_on.end_of_month.end_of_day,
        balance: 5_000 + (index * 250),
        currency_code: currency,
        source_kind: "manual",
        status: "trusted",
        created_at: timestamp,
        updated_at: timestamp
      }
    end
    BalanceObservation.insert_all!(rows)
  end

  def insert_all_in_batches(model, rows)
    rows.each_slice(500) { |batch| model.insert_all!(batch) }
  end
end
