module Overview
  class PageData
    TEMPLATE_TYPES = %i[pay_schedules subscriptions monthly_bills payment_plans credit_cards].freeze

    def initialize(user:, today: Date.current)
      @user = user
      @today = today
    end

    def call
      data = {
        budget_months: budget_months,
        current_month: current_month,
        recent_months: budget_months.first(4),
        current_month_entries: current_month_entries
      }

      data.merge!(review_counts)
      data.merge!(template_counts)
      data.merge!(template_progress)
      data.merge!(account_summary)
      data.merge!(cashflow_summary)
      data[:onboarding_visible] = data[:current_month].nil? || data[:accounts].empty? || data[:template_total].zero? || data[:linked_template_total].zero?
      data[:next_step] = NextStepPolicy.new(context: data).call
      data
    end

    private

    attr_reader :today, :user

    def budget_months
      @budget_months ||= user.budget_months.includes(:expense_entries).recent_first.to_a
    end

    def current_month
      @current_month ||= user.budget_months.find_by(month_on: today.beginning_of_month) || budget_months.first
    end

    def current_month_entries
      @current_month_entries ||= current_month ? current_month.expense_entries.to_a : []
    end

    def review_counts
      due_planned_count = current_month_entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on <= today }
      missing_details_count = current_month_entries.count { |entry| entry.occurred_on.blank? || entry.category.blank? || entry.payee.blank? }
      paid_missing_actual_count = current_month_entries.count { |entry| entry.paid? && entry.actual_amount.blank? }

      {
        due_planned_count: due_planned_count,
        missing_details_count: missing_details_count,
        paid_missing_actual_count: paid_missing_actual_count,
        review_attention_count: due_planned_count + missing_details_count + paid_missing_actual_count,
        manual_entries_count: current_month_entries.count { |entry| entry.source_file.blank? },
        linked_entries_count: current_month_entries.count { |entry| entry.source_account_id.present? },
        linked_paid_entries_count: current_month_entries.count { |entry| entry.source_account_id.present? && entry.paid? }
      }
    end

    def template_counts
      counts = {
        pay_schedules: user.pay_schedules.count,
        subscriptions: user.subscriptions.count,
        monthly_bills: user.monthly_bills.count,
        payment_plans: user.payment_plans.count,
        credit_cards: user.credit_cards.count
      }

      linked_counts = {
        pay_schedules: user.pay_schedules.where.not(linked_account_id: nil).count,
        subscriptions: user.subscriptions.where.not(linked_account_id: nil).count,
        monthly_bills: user.monthly_bills.where.not(linked_account_id: nil).count,
        payment_plans: user.payment_plans.where.not(linked_account_id: nil).count,
        credit_cards: user.credit_cards.where.not(linked_account_id: nil).count
      }

      {
        template_counts: counts,
        template_total: counts.values.sum,
        linked_template_counts: linked_counts,
        linked_template_total: linked_counts.values.sum
      }
    end

    def template_progress
      return { template_actions_completed: 0 } unless current_month

      template_actions_completed = [
        template_coverage_for_type(:pay_schedules).fetch(:complete),
        template_coverage_for_type(:subscriptions).fetch(:complete),
        template_coverage_for_type(:monthly_bills).fetch(:complete),
        template_coverage_for_type(:payment_plans).fetch(:complete),
        matching_template_entries(:credit_cards).any?
      ].count(true)

      { template_actions_completed: template_actions_completed }
    end

    def account_summary
      @account_summary ||= Accounts::Summary.new(user: user).call
    end

    def cashflow_summary
      overview_cashflow_year = today.year
      year_budget_months = user.budget_months
        .where(month_on: Date.new(overview_cashflow_year, 1, 1)..Date.new(overview_cashflow_year, 12, 31))
        .includes(:expense_entries)
        .order(:month_on)
        .to_a

      {
        overview_cashflow_year: overview_cashflow_year,
        year_budget_months: year_budget_months,
        year_cashflow_payload: YearCashflowSankey.cached_payload(
          user: user,
          year: overview_cashflow_year,
          budget_months: year_budget_months
        )
      }
    end

    def template_coverage_for_type(template_type)
      templates = templates_for_type(template_type)
      matched = templates.count do |template|
        current_month_entries.any? do |entry|
          template_matches_entry?(template, entry)
        end
      end

      {
        total: templates.size,
        matched: matched,
        remaining: [ templates.size - matched, 0 ].max,
        complete: templates.any? && matched == templates.size
      }
    end

    def matching_template_entries(template_type)
      current_month_entries.select do |entry|
        templates_for_type(template_type).any? do |template|
          template_matches_entry?(template, entry)
        end
      end
    end

    def templates_for_type(template_type)
      case template_type
      when :pay_schedules
        user.pay_schedules.active_only.to_a
      when :subscriptions
        user.subscriptions.active_only.to_a
      when :monthly_bills
        user.monthly_bills.active_only.select { |bill| bill.scheduled_for_month?(current_month.month_on) }
      when :payment_plans
        user.payment_plans.active_only.to_a
      when :credit_cards
        user.credit_cards.active_only.to_a
      else
        []
      end
    end

    def template_matches_entry?(template, entry)
      return template.matches_entry?(entry) if template.is_a?(CreditCard)

      template.matches_entry?(entry, month_on: current_month.month_on)
    end
  end
end
