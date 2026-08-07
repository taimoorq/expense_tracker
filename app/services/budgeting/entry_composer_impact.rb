module Budgeting
  class EntryComposerImpact
    Result = Data.define(:amount, :month_delta, :month_label, :account_lines, :status_label)

    def self.call(expense_entry:, budget_month: expense_entry.budget_month)
      new(expense_entry: expense_entry, budget_month: budget_month).call
    end

    def initialize(expense_entry:, budget_month:)
      @expense_entry = expense_entry
      @budget_month = budget_month
    end

    def call
      Result.new(
        amount: amount,
        month_delta: month_delta,
        month_label: month_label,
        account_lines: account_lines,
        status_label: status_label
      )
    end

    private

    attr_reader :expense_entry, :budget_month

    def amount
      expense_entry.effective_amount.to_d
    end

    def month_delta
      return 0.to_d if expense_entry.skipped?

      expense_entry.income? ? amount : -amount
    end

    def month_label
      return "No change to #{budget_month.label}" if expense_entry.skipped? || amount.zero?
      return "Adds to money available in #{budget_month.label}" if expense_entry.income?

      "Reduces money available in #{budget_month.label}"
    end

    def account_lines
      [ expense_entry.source_account, expense_entry.destination_account ].compact.uniq.map do |account|
        impact = Accounts::EntryImpact.new(account: account, entry: expense_entry)
        { account: account, delta: impact.delta, movement_type: impact.movement_type }
      end
    end

    def status_label
      {
        "planned" => "Planned amounts affect the month plan but not current balances.",
        "paid" => "Paid amounts affect the month and linked account balances.",
        "skipped" => "Skipped entries stay visible without changing totals or balances."
      }.fetch(expense_entry.status.to_s, "Choose a status to see its effect.")
    end
  end
end
