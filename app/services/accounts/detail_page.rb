module Accounts
  class DetailPage
    DETAIL_VIEWS = %w[overview activity insights manage].freeze

    def initialize(account:, as_of: Date.current, range: Accounts::MovementTimeline::DEFAULT_RANGE, view: "overview")
      @account = account
      @user = account.user
      @as_of = as_of
      @range = range
      @view = view.to_s.in?(DETAIL_VIEWS) ? view.to_s : "overview"
    end

    def call
      common_data.merge(view_data)
    end

    private

    attr_reader :account, :as_of, :range, :user, :view

    def common_data
      {
        balance_summary: balance_summary,
        account_story: account_story
      }
    end

    def view_data
      case view
      when "overview"
        {
          credit_card_progress: credit_card_progress,
          movement_timeline: movement_timeline,
          recent_activity: recent_activity
        }
      when "insights"
        { activity_insights: activity_insights }
      when "manage"
        {
          balance_history_rows: balance_history_rows,
          connected_templates: connected_templates,
          connected_templates_count: connected_templates_count,
          import_history: import_history
        }
      else
        {}
      end
    end

    def account_story
      @account_story ||= Accounts::AccountStoryPresenter.new(account: account).call
    end

    def movement_timeline
      @movement_timeline ||= Accounts::MovementTimeline.new(account: account, range: range, as_of: as_of).call
    end

    def recent_activity
      @recent_activity ||= Accounts::ActivityLedgerQuery.new(account: account, limit: 5).call
    end

    def balance_history_rows
      @balance_history_rows ||= Accounts::BalanceHistory.new(account: account, as_of: as_of).call.fetch(:rows)
    end

    def balance_summary
      @balance_summary ||= Accounts::BalanceResolver.new(account: account, as_of: as_of).call.to_h
    end

    def credit_card_progress
      return nil unless account.credit_card?
      return nil unless balance_summary.fetch(:balance_available, balance_summary[:balance_source] != :none)

      @credit_card_progress ||= Accounts::CreditCardProgress.new(
        account: account,
        balance_summary: balance_summary,
        as_of: as_of
      ).call
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

    def activity_insights
      @activity_insights ||= Accounts::ActivityInsights::Report.new(account: account).call
    end

    def import_history
      @import_history ||= account.account_activity_imports.order(created_at: :desc).limit(6).to_a
    end
  end
end
