module Accounts
  class CreditCardProgress
    def initialize(account:, balance_summary:, as_of: Date.current)
      @account = account
      @balance_summary = balance_summary
      @as_of = as_of
      @user = account.user
    end

    def call
      {
        month_label: as_of.strftime("%B %Y"),
        paid_down_this_month: paid_down_this_month,
        added_this_month: added_this_month,
        net_paydown_this_month: paid_down_this_month - added_this_month,
        starting_debt: starting_debt,
        current_debt: current_debt,
        projected_debt: projected_debt,
        progress_percent: progress_percent,
        snapshot: snapshot,
        snapshot_needed?: snapshot.blank?,
        improved_since_snapshot?: progress_percent.to_i.positive?,
        planned_payment_remaining_this_month: planned_payment_remaining_this_month
      }
    end

    private

    attr_reader :account, :balance_summary, :as_of, :user

    def paid_down_this_month
      @paid_down_this_month ||= month_entries
        .select { |entry| entry.paid? && entry.destination_account_id == account.id }
        .sum { |entry| entry.effective_amount.to_d }
    end

    def added_this_month
      @added_this_month ||= month_entries
        .select { |entry| entry.paid? && entry.source_account_id == account.id && !entry.income? }
        .sum { |entry| entry.effective_amount.to_d }
    end

    def planned_payment_remaining_this_month
      @planned_payment_remaining_this_month ||= month_entries
        .select { |entry| entry.planned? && entry.destination_account_id == account.id && entry.occurred_on >= as_of }
        .sum { |entry| entry.effective_amount.to_d }
    end

    def progress_percent
      return nil if snapshot.blank?
      return 100 if starting_debt.zero? && current_debt.zero?
      return 0 if starting_debt.zero?

      (((starting_debt - current_debt) / starting_debt) * 100).clamp(0, 100).round
    end

    def starting_debt
      @starting_debt ||= debt_amount(balance_summary.fetch(:base_balance))
    end

    def current_debt
      @current_debt ||= debt_amount(balance_summary.fetch(:current_balance))
    end

    def projected_debt
      @projected_debt ||= debt_amount(balance_summary.fetch(:projected_balance))
    end

    def snapshot
      @snapshot ||= balance_summary.fetch(:snapshot)
    end

    def month_entries
      @month_entries ||= user.expense_entries
                             .where("source_account_id = :account_id OR destination_account_id = :account_id", account_id: account.id)
                             .where(status: [ ExpenseEntry.statuses[:paid], ExpenseEntry.statuses[:planned] ])
                             .where.not(occurred_on: nil)
                             .where(occurred_on: as_of.beginning_of_month..as_of.end_of_month)
                             .to_a
    end

    def debt_amount(balance)
      [ -balance.to_d, 0.to_d ].max
    end
  end
end
