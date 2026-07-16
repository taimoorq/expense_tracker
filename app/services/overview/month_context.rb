module Overview
  class MonthContext
    def initialize(user:, today: Date.current)
      @user = user
      @today = today
    end

    def call
      {
        budget_months: budget_months,
        current_month: current_month,
        recent_months: budget_months.first(4),
        current_month_entries: current_month_entries
      }
    end

    private

    attr_reader :today, :user

    def budget_months
      @budget_months ||= user.budget_months.recent_first.to_a
    end

    def current_month
      @current_month ||= budget_months.find { |month| month.month_on == today.beginning_of_month } || budget_months.first
    end

    def current_month_entries
      @current_month_entries ||= begin
        entries = current_month ? user.expense_entries.where(budget_month_id: current_month.id).to_a : []
        entries_with_source_accounts = entries.select { |entry| entry.source_account_id.present? }
        if entries_with_source_accounts.any?
          ActiveRecord::Associations::Preloader.new(records: entries_with_source_accounts, associations: :source_account).call
        end
        entries
      end
    end
  end
end
