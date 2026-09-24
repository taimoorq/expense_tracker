module Activity
  class BankReviewQuery
    PER_PAGE = 25
    attr_reader :workspace, :user, :account_id, :starts_on, :ends_on, :page, :pending, :ignored

    def initialize(workspace:, user:, account_id: nil, starts_on: nil, ends_on: nil, page: nil, pending: false, ignored: false)
      @workspace, @user, @account_id, @starts_on, @ends_on, @pending = workspace, user, account_id, starts_on, ends_on, pending
      @ignored = ignored
      @page = [ page.to_i, 1 ].max
    end

    def scope
      rows = workspace.provider_transactions.joins(:connected_account).where(connected_accounts: { state: "mapped" }).where.not(connected_accounts: { account_id: nil })
      rows = rows.where(connected_accounts: { account_id: account_id }) if account_id
      rows = rows.where("COALESCE(provider_transactions.posted_at, provider_transactions.transacted_at) >= ?", starts_on.in_time_zone(workspace.time_zone)) if starts_on
      rows = rows.where("COALESCE(provider_transactions.posted_at, provider_transactions.transacted_at) < ?", ends_on.next_day.in_time_zone(workspace.time_zone)) if ends_on
      rows.includes(:connected_account).order(fetched_at: :desc, id: :desc)
    end

    def transactions
      scope.where(state: ignored ? %w[ignored] : %w[review changed], pending: pending).offset((page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def total
      scope.where(state: ignored ? %w[ignored] : %w[review changed], pending: pending).count
    end

    def accepted_transactions
      scope.where.not(financial_transaction_id: nil).limit(50)
    end

    def entries
      user.expense_entries.where(occurred_on: 90.days.ago.to_date..Date.current.end_of_month).order(occurred_on: :desc).limit(300)
    end

    def transfer_candidates
      workspace.provider_transactions.where(pending: false).where.not(posted_at: nil).includes(:connected_account).order(fetched_at: :desc).limit(300)
    end

    def self.existing_candidates(source)
      source.budget_workspace.financial_transactions.state_posted.joins(:account_postings)
        .where(account_postings: { account_id: source.connected_account.account_id, amount: source.amount, currency_code: source.currency })
        .where.not(id: source.financial_transaction_id).order(effective_on: :desc).limit(50)
    end
  end
end
