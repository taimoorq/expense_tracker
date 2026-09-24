module Accounts
  # Balances are calculated across the account's whole history, not the visible
  # (possibly filtered) rows. All amounts remain decimals until view formatting.
  class EntryRunningBalances
    Event = Data.define(:key, :date, :kind, :amount, :entries, :order)
    Value = Data.define(:account, :amount, :effective_on, :reported_on, :message)

    def self.call(budget_month:, entries:)
      new(budget_month: budget_month, entries: entries).call
    end

    def initialize(budget_month:, entries:)
      @budget_month = budget_month
      @entries = entries.to_a
    end

    def call
      values = entries.index_with { |entry| unavailable(entry) }.transform_keys(&:id)
      accounts.each do |account|
        inputs = RunningBalanceInputs.new(account: account, through_on: through_on)
        account_values(account, inputs.events).each do |entry_id, value|
          values[entry_id] = value if values.key?(entry_id)
        end
      end
      values
    end

    private

    attr_reader :budget_month, :entries

    def through_on
      # Recurring paychecks may legitimately belong to an adjacent calendar day.
      @through_on ||= [ budget_month.month_on.end_of_month, *entries.filter_map(&:occurred_on) ].max
    end

    def accounts
      @accounts ||= begin
        records = budget_month.user.accounts.where(id: entries.filter_map(&:source_account_id).uniq).includes(:budget_workspace).to_a
        target, legacy = records.partition { |account| account.budget_workspace&.target_reads_enabled? }
        ActiveRecord::Associations::Preloader.new(records: target, associations: :connected_account).call if target.any?
        ActiveRecord::Associations::Preloader.new(records: legacy, associations: :account_activity_imports).call if legacy.any?
        records
      end
    end

    def unavailable(entry)
      message = if entry.source_account_id.blank?
        "Link this entry to an account to see its balance."
      elsif entry.occurred_on.blank?
        "Add a date to this entry to see its balance."
      else
        "No earlier reported balance or linked movement is available. Check this account's balances and Activity."
      end
      Value.new(account: nil, amount: nil, effective_on: nil, reported_on: nil, message: message)
    end

    def account_values(account, events)
      return {} if account.budget_workspace&.target_reads_enabled? && Accounts::BankPosition.new(account: account, as_of: through_on).unresolved?

      reports, movements = events.partition { |event| event.kind == :report }
      reports = reports.group_by { |event| [ event.date, event.order.first ] }.values.map { |values| values.max_by(&:key) }
      ordered = (reports + movements).sort_by { |event| [ event.date, event.order, event.key ] }
      balance = nil
      reported_on = nil
      values = {}

      ordered.each do |event|
        if event.kind == :report
          # A reported balance replaces the prior forecast. Earlier plans must
          # not be carried into a newly confirmed starting point.
          balance = event.amount
          reported_on = event.date
        else
          balance += event.amount unless balance.nil?
        end
        event.entries.each do |entry|
          next unless entry.source_account_id == account.id

          message = balance.nil? ? "Report a balance before this date in Accounts to start running balances." :
            "#{account.name}: projected balance after movement on #{event.date}, based on the reported balance through #{reported_on}. Includes outstanding plans and other account activity."
          values[entry.id] = Value.new(account: account, amount: balance, effective_on: event.date,
            reported_on: reported_on, message: message)
        end
      end
      values
    end
  end
end
