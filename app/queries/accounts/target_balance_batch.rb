module Accounts
  class TargetBalanceBatch
    def self.call(accounts:, as_of: Date.current)
      new(accounts: accounts, as_of: as_of).call
    end

    def initialize(accounts:, as_of:)
      @accounts = Array(accounts)
      @as_of = as_of.to_date
    end

    def call
      accounts.index_with { |account| result_for(account) }
    end

    private

    attr_reader :accounts, :as_of

    def account_ids
      @account_ids ||= accounts.map(&:id)
    end

    def workspace
      @workspace ||= begin
        value = accounts.first&.budget_workspace
        if accounts.any? { |account| account.budget_workspace_id != value&.id }
          raise ArgumentError, "accounts must belong to one target workspace"
        end
        value
      end
    end

    def observations
      return {} if account_ids.empty?

      @observations ||= BalanceObservation
        .where(account_id: account_ids, status: "trusted")
        .where(effective_through_at: ..as_of.end_of_day)
        .select("DISTINCT ON (account_id) balance_observations.*")
        .order(:account_id, effective_through_at: :desc, created_at: :desc)
        .index_by(&:account_id)
    end

    def posting_rows
      @posting_rows ||= begin
        return [] if observations.empty?

        workspace.account_postings
          .joins(:financial_transaction)
          .where(account_id: account_ids, financial_transactions: { state: "posted", effective_on: earliest_activity_on..as_of })
          .pluck(:account_id, :amount, "financial_transactions.effective_on", :financial_transaction_id, "financial_transactions.origin_kind")
      end
    end

    def postings_by_account
      @postings_by_account ||= posting_rows.group_by(&:first)
    end

    def planned_items
      @planned_items ||= begin
        return [] if workspace.blank? || account_ids.empty?

        workspace.budget_items
          .where(state: "open", scheduled_on: as_of..)
          .where("intended_source_account_id IN (:ids) OR intended_destination_account_id IN (:ids)", ids: account_ids)
          .where(<<~SQL.squish)
            NOT EXISTS (
              SELECT 1
              FROM budget_allocations
              INNER JOIN financial_transactions
                ON financial_transactions.id = budget_allocations.financial_transaction_id
              WHERE budget_allocations.budget_item_id = budget_items.id
                AND financial_transactions.state = 'posted'
            )
          SQL
          .to_a
      end
    end

    def planned_by_account
      @planned_by_account ||= account_ids.index_with do |account_id|
        planned_items.select do |item|
          item.intended_source_account_id == account_id || item.intended_destination_account_id == account_id
        end
      end
    end

    def earliest_activity_on
      observations.values.map { |observation| observation.effective_through_at.to_date.next_day }.min
    end

    def result_for(account)
      observation = observations[account.id]
      return without_balance_source(account) if observation.blank?

      postings = relevant_postings(account, observation)
      plans = planned_by_account.fetch(account.id)
      posted_delta = postings.sum { |_account_id, amount, _date, _transaction_id, _origin| amount.to_d }
      planned_delta = plans.sum { |item| planned_item_delta(account, item) }
      current_balance = observation.balance.to_d + posted_delta
      source = balance_source(observation, postings)

      Accounts::BalanceResolver::Result.new(
        account: account,
        snapshot: nil,
        balance_source: source,
        balance_source_label: source_label(source),
        balance_source_record: observation,
        balance_source_recorded_on: observation.effective_through_at.to_date,
        activity_through_on: postings.map { |row| row[2] }.max,
        base_balance: observation.balance.to_d,
        paid_delta: posted_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: postings.map { |row| row[3] }.uniq.size,
        planned_entries_count: plans.size,
        balance_available: true
      )
    end

    def relevant_postings(account, observation)
      postings_by_account.fetch(account.id, []).select do |_account_id, _amount, effective_on, _transaction_id, _origin|
        effective_on > observation.effective_through_at.to_date
      end
    end

    def planned_item_delta(account, item)
      delta = 0.to_d
      if item.intended_source_account_id == account.id
        delta += item.flow_kind_income? ? item.planned_amount : -item.planned_amount
      end
      delta += item.planned_amount if item.intended_destination_account_id == account.id
      delta
    end

    def balance_source(observation, postings)
      return :institution_import if observation.source_kind_institution_file?
      return :imported_activity if postings.any? { |row| row[4] == "institution_import" }

      :snapshot
    end

    def source_label(source)
      {
        institution_import: "Institution import",
        imported_activity: "Imported activity",
        snapshot: "Manual snapshot"
      }.fetch(source)
    end

    def without_balance_source(account)
      Accounts::BalanceResolver::Result.new(
        account: account,
        snapshot: nil,
        balance_source: :none,
        balance_source_label: "No balance source",
        balance_source_record: nil,
        balance_source_recorded_on: nil,
        activity_through_on: nil,
        base_balance: 0.to_d,
        paid_delta: 0.to_d,
        planned_delta: 0.to_d,
        current_balance: 0.to_d,
        projected_balance: 0.to_d,
        paid_entries_count: 0,
        planned_entries_count: 0,
        balance_available: false
      )
    end
  end
end
