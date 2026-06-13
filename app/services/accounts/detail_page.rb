module Accounts
  class DetailPage
    LINKED_ENTRY_LIMIT = 150

    def initialize(account:, as_of: Date.current)
      @account = account
      @user = account.user
      @as_of = as_of
    end

    def call
      {
        balance_summary: balance_summary,
        balance_history_rows: balance_history.fetch(:rows),
        credit_card_progress: credit_card_progress,
        linked_entries: linked_entries,
        linked_entries_net: linked_entries_net,
        connected_templates: connected_templates,
        connected_templates_count: connected_templates_count
      }
    end

    private

    attr_reader :account, :as_of, :user

    def balance_history
      @balance_history ||= Accounts::BalanceHistory.new(account: account, as_of: as_of).call
    end

    def balance_summary
      @balance_summary ||= balance_history.fetch(:summary)
    end

    def credit_card_progress
      return nil unless account.credit_card?

      @credit_card_progress ||= Accounts::CreditCardProgress.new(
        account: account,
        balance_summary: balance_summary,
        as_of: as_of
      ).call
    end

    def linked_entries
      @linked_entries ||= user.expense_entries
                             .where("source_account_id = :account_id OR destination_account_id = :account_id", account_id: account.id)
                             .includes(:budget_month, :source_account, :destination_account, :source_template)
                             .order(occurred_on: :desc, created_at: :desc)
                             .limit(LINKED_ENTRY_LIMIT)
    end

    def linked_entries_net
      @linked_entries_net ||= linked_entries.sum { |entry| account.account_delta_for(entry) }
    end

    def connected_templates
      @connected_templates ||= {
        "Pay Schedules" => user.pay_schedules.where(linked_account_id: account.id).order(active: :desc, name: :asc).to_a,
        "Subscriptions" => user.subscriptions.where(linked_account_id: account.id).order(active: :desc, due_day: :asc, name: :asc).to_a,
        "Monthly Bills" => user.monthly_bills.where(linked_account_id: account.id).order(active: :desc, due_day: :asc, name: :asc).to_a,
        "Payment Plans" => user.payment_plans.where(linked_account_id: account.id).order(active: :desc, due_day: :asc, name: :asc).to_a,
        "Credit Cards" => user.credit_cards.where(linked_account_id: account.id).order(active: :desc, priority: :asc, name: :asc).to_a,
        "Credit Card Payments" => user.credit_cards.where(payment_account_id: account.id).order(active: :desc, priority: :asc, name: :asc).to_a
      }
    end

    def connected_templates_count
      @connected_templates_count ||= connected_templates.values.sum(&:size)
    end
  end
end
