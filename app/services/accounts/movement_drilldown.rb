module Accounts
  class MovementDrilldown
    TYPE_LABELS = Accounts::EntryImpact::MOVEMENT_TITLES

    def initialize(budget_month:, account:, movement_type:)
      @budget_month = budget_month
      @account = account
      @movement_type = movement_type.to_s
    end

    def call
      entries = matching_entries

      {
        movement_type: movement_type,
        title: TYPE_LABELS.fetch(movement_type),
        budget_month: budget_month,
        account: account,
        entries: entries,
        total: entries.sum { |entry| entry.effective_amount.to_d },
        entry_count: entries.size
      }
    end

    private

    attr_reader :budget_month, :account, :movement_type

    def matching_entries
      entries.select { |entry| matches_movement?(entry) }
    end

    def entries
      @entries ||= budget_month.expense_entries
                             .includes(:source_account, :destination_account, :source_template)
                             .where.not(occurred_on: nil)
                             .order(:occurred_on, :created_at)
                             .to_a
    end

    def matches_movement?(entry)
      Accounts::EntryImpact.new(account: account, entry: entry).movement_type == movement_type
    end
  end
end
