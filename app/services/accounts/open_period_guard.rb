module Accounts
  class OpenPeriodGuard
    def self.call(workspace:, dates:)
      months = dates.compact.map { |date| date.to_date.beginning_of_month }.uniq
      if workspace.budget_periods.where(starts_on: months, state: %w[closed closing]).exists?
        raise ArgumentError, "Reopen the affected month before changing its activity."
      end
    end
  end
end
