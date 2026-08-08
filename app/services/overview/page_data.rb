module Overview
  class PageData
    def initialize(user:, today: Date.current, account_flow_month_window: Overview::AccountFlowWindow::DEFAULT_MONTH_WINDOW)
      @user = user
      @today = today
      @account_flow_month_window = account_flow_month_window
    end

    def call
      data = month_context
      data.merge!(review_summary)
      data.merge!(template_summary)
      data.merge!(account_summary)
      data.merge!(account_flow_summary)
      data.merge!(cashflow_summary)
      data[:financial_rhythm] = user.financial_rhythm
      onboarding = Overview::OnboardingProgress.call(user: user, data: data)
      data[:onboarding_visible] = onboarding.visible
      data[:onboarding_progress] = onboarding
      data[:recent_operations] = Platform::Operations::Status.recent(user: user)
      data[:next_step] = NextStepPolicy.new(context: data).call
      data
    end

    private

    attr_reader :account_flow_month_window, :today, :user

    def month_context
      @month_context ||= Overview::MonthContext.new(user: user, today: today).call
    end

    def current_month
      month_context.fetch(:current_month)
    end

    def current_month_entries
      month_context.fetch(:current_month_entries)
    end

    def review_summary
      if target_period_context.present?
        return Overview::TargetReviewSummary.call(period: target_period_context.period, today: today)
      end

      @review_summary ||= Overview::ReviewSummary.new(entries: current_month_entries, today: today).call
    end

    def target_period_context
      return @target_period_context if defined?(@target_period_context)

      @target_period_context = current_month && Budgeting::TargetPeriodContext.call(
        user: user,
        budget_month: current_month
      )
    end

    def template_summary
      @template_summary ||= Overview::TemplateSummary.new(
        user: user,
        current_month: current_month,
        current_month_entries: current_month_entries
      ).call
    end

    def account_summary
      @account_summary ||= Accounts::Summary.new(user: user).call
    end

    def account_flow_summary
      @account_flow_summary ||= Overview::AccountFlowWindow.new(
        user: user,
        month_window: account_flow_month_window
      ).call
    end

    def cashflow_summary
      @cashflow_summary ||= Overview::CashflowSummary.new(user: user, year: today.year).call
    end
  end
end
