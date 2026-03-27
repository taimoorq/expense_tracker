class OverviewController < ApplicationController
  include ApplicationHelper

  def show
    @budget_months = current_user.budget_months.includes(:expense_entries).recent_first.to_a
    @current_month = current_user.budget_months.find_by(month_on: Date.current.beginning_of_month) || @budget_months.first
    @recent_months = @budget_months.first(4)
    @current_month_entries = @current_month ? @current_month.expense_entries.to_a : []

    @due_planned_count = @current_month_entries.count { |entry| entry.planned? && entry.occurred_on.present? && entry.occurred_on <= Date.current }
    @missing_details_count = @current_month_entries.count { |entry| entry.occurred_on.blank? || entry.category.blank? || entry.payee.blank? }
    @paid_missing_actual_count = @current_month_entries.count { |entry| entry.paid? && entry.actual_amount.blank? }
    @review_attention_count = @due_planned_count + @missing_details_count + @paid_missing_actual_count
    @manual_entries_count = @current_month_entries.count { |entry| entry.source_file.blank? }

    @template_counts = {
      pay_schedules: current_user.pay_schedules.count,
      subscriptions: current_user.subscriptions.count,
      monthly_bills: current_user.monthly_bills.count,
      payment_plans: current_user.payment_plans.count,
      credit_cards: current_user.credit_cards.count
    }
    @template_total = @template_counts.values.sum
    @linked_template_counts = {
      pay_schedules: current_user.pay_schedules.where.not(linked_account_id: nil).count,
      subscriptions: current_user.subscriptions.where.not(linked_account_id: nil).count,
      monthly_bills: current_user.monthly_bills.where.not(linked_account_id: nil).count,
      payment_plans: current_user.payment_plans.where.not(linked_account_id: nil).count,
      credit_cards: current_user.credit_cards.where.not(linked_account_id: nil).count
    }
    @linked_template_total = @linked_template_counts.values.sum
    @linked_entries_count = @current_month_entries.count { |entry| entry.source_account_id.present? }
    @linked_paid_entries_count = @current_month_entries.count { |entry| entry.source_account_id.present? && entry.paid? }

    @template_actions_completed = 0
    if @current_month
      # Use same logic as plan_and_edit_panel
      paycheck_coverage = template_coverage_for_type(@current_month, :pay_schedules, @current_month_entries)
      subscription_coverage = template_coverage_for_type(@current_month, :subscriptions, @current_month_entries)
      monthly_bill_coverage = template_coverage_for_type(@current_month, :monthly_bills, @current_month_entries)
      payment_plan_coverage = template_coverage_for_type(@current_month, :payment_plans, @current_month_entries)
      matching_credit_card_entries = matching_template_entries(@current_month, :credit_cards, @current_month_entries)
      has_generated_paychecks = paycheck_coverage[:complete]
      has_generated_subscriptions = subscription_coverage[:complete]
      has_generated_monthly_bills = monthly_bill_coverage[:complete]
      has_generated_payment_plans = payment_plan_coverage[:complete]
      has_estimated_credit_cards = matching_credit_card_entries.any?
      @template_actions_completed = [ has_generated_paychecks, has_generated_subscriptions, has_generated_monthly_bills, has_generated_payment_plans, has_estimated_credit_cards ].count(true)
    end

    @accounts = current_user.accounts.includes(:account_snapshots).active_first.to_a
    @net_worth_accounts = @accounts.select(&:include_in_net_worth)
    @assets_total = @net_worth_accounts.select(&:asset?).sum(&:display_balance)
    @liabilities_total = @net_worth_accounts.select(&:liability?).sum { |account| account.display_balance.abs }
    @net_worth_total = @assets_total - @liabilities_total
    @latest_snapshot = current_user.account_snapshots.joins(:account).merge(Account.where(user: current_user)).order(recorded_on: :desc, created_at: :desc).first
    @accounts_with_snapshots_count = @accounts.count(&:latest_snapshot)
    @accounts_missing_snapshots_count = @accounts.count - @accounts_with_snapshots_count
    @onboarding_visible = @current_month.nil? || @accounts.empty? || @template_total.zero? || @linked_template_total.zero?
    @overview_cashflow_year = Date.current.year
    @year_budget_months = current_user.budget_months
      .where(month_on: Date.new(@overview_cashflow_year, 1, 1)..Date.new(@overview_cashflow_year, 12, 31))
      .includes(:expense_entries)
      .order(:month_on)
      .to_a
    @year_cashflow_payload = YearCashflowSankey.cached_payload(
      user: current_user,
      year: @overview_cashflow_year,
      budget_months: @year_budget_months
    )

    @next_step = next_step_definition
  end

  private

  def next_step_definition
    if @accounts.empty?
      return {
        badge: "Start here",
        title: "Add your first account",
        description: "Start with the real accounts you expect to use so templates and month entries have somewhere to link later.",
        primary_label: "Set up Accounts",
        primary_path: accounts_path,
        secondary_label: "Create Account",
        secondary_path: new_account_path
      }
    end

    if @template_total.zero?
      return {
        badge: "Recommended",
        title: "Set up planning templates",
        description: "Add the incoming and outgoing items you expect each month first, then your first month can pull that recurring structure in immediately.",
        primary_label: "Open Planning Templates",
        primary_path: planning_templates_path,
        secondary_label: "Open Accounts",
        secondary_path: accounts_path
      }
    end

    if @linked_template_total.zero?
      return {
        badge: "Recommended",
        title: "Link templates to accounts",
        description: "Link the templates you just set up so generated month entries and account views stay aligned from the start.",
        primary_label: "Manage Planning Templates",
        primary_path: planning_templates_path,
        secondary_label: "Open Accounts",
        secondary_path: accounts_path
      }
    end

    if @current_month.nil?
      return {
        badge: "Next step",
        title: "Create your first month",
        description: "Once accounts and templates are ready, create the month and import the recurring template items into it.",
        primary_label: "Create Month",
        primary_path: new_budget_month_path,
        secondary_label: "Open Planning Templates",
        secondary_path: planning_templates_path
      }
    end

    if @current_month_entries.empty?
      return {
        badge: "Next step",
        title: "Import templates into #{@current_month.label}",
        description: "Start the month by pulling in the recurring templates you already saved, then adjust the entries from there.",
        primary_label: "Open Plan and Edit",
        primary_path: budget_month_path(@current_month, tab: "entries"),
        secondary_label: "Add Entry with Wizard",
        secondary_path: new_wizard_budget_month_expense_entries_path(@current_month),
        secondary_turbo_frame: "entry_wizard_modal"
      }
    end

    if @review_attention_count.positive?
      return {
        badge: "Needs review",
        title: "Review #{@review_attention_count} attention item#{@review_attention_count == 1 ? "" : "s"}",
        description: "Some entries are due, missing details, or marked paid without an actual amount.",
        primary_label: "Open Plan and Edit",
        primary_path: budget_month_path(@current_month, tab: "entries"),
        secondary_label: "Open Budget",
        secondary_path: budget_month_path(@current_month, tab: "timeline")
      }
    end

    if @manual_entries_count.zero?
      return {
        badge: "Next step",
        title: "Add one-off items",
        description: "Recurring items are in place. Add exceptions, adjustments, or irregular spending next.",
        primary_label: "Add Entry with Wizard",
        primary_path: new_wizard_budget_month_expense_entries_path(@current_month),
        primary_turbo_frame: "entry_wizard_modal",
        secondary_label: "Open Budget",
        secondary_path: budget_month_path(@current_month, tab: "timeline")
      }
    end

    {
      badge: "On track",
      title: "Keep the month current",
      description: "Make manual adjustments as the month changes, mark items paid as they happen, and keep review views current.",
      primary_label: "Open Budget",
      primary_path: budget_month_path(@current_month, tab: "timeline"),
      secondary_label: "Open Calendar",
      secondary_path: budget_month_path(@current_month, tab: "calendar")
    }
  end
end
