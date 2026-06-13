module Accounts
  class MovementDrilldown
    TYPE_LABELS = {
      "credit_card_added" => "Credit card charges added",
      "credit_card_paid" => "Credit card payments made",
      "credit_card_planned" => "Planned credit card payments",
      "bank_money_in" => "Bank money in",
      "bank_paid_out" => "Bank paid out",
      "bank_left_to_pay" => "Bank left to pay"
    }.freeze

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
      return false if entry.skipped?

      case movement_type
      when "credit_card_added"
        entry.paid? && entry.source_account_id == account.id && account.credit_card? && !entry.income?
      when "credit_card_paid"
        entry.paid? && entry.destination_account_id == account.id && account.credit_card?
      when "credit_card_planned"
        entry.planned? && entry.destination_account_id == account.id && account.credit_card?
      when "bank_money_in"
        entry.paid? && entry.source_account_id == account.id && account.asset? && entry.income?
      when "bank_paid_out"
        entry.paid? && entry.source_account_id == account.id && account.asset? && !entry.income?
      when "bank_left_to_pay"
        entry.planned? && entry.source_account_id == account.id && account.asset? && !entry.income?
      else
        false
      end
    end
  end
end
