class BudgetMonthClosesController < ApplicationController
  before_action :load_context

  def show
    @readiness = Budgeting::CloseReadiness.call(period: @target_period)
    @active_close = @target_period.month_closes.state_closed
      .includes(:item_snapshots, :transaction_snapshots)
      .first
    @summary = @active_close&.report_summary || @readiness.summary
    @unresolved_account_count = @active_close&.unresolved_count || @readiness.unresolved_account_count
  end

  def create
    Budgeting::ClosePeriod.call(
      workspace: @workspace,
      actor_membership: @membership,
      budget_period: @target_period,
      idempotency_key: "ui:close-period:#{@target_period.id}:#{@target_period.lock_version}"
    )
    redirect_to budget_month_path(@budget_month), notice: "#{@budget_month.label} closed with a frozen summary."
  rescue Budgeting::ClosePeriod::InvalidState => error
    redirect_to budget_month_month_close_path(@budget_month), alert: error.message
  end

  def reopen
    Budgeting::ReopenPeriod.call(
      workspace: @workspace,
      actor_membership: @membership,
      budget_period: @target_period,
      idempotency_key: "ui:reopen-period:#{@target_period.id}:#{@target_period.lock_version}"
    )
    redirect_to budget_month_path(@budget_month), notice: "#{@budget_month.label} reopened. Its prior close remains in history."
  rescue Budgeting::ClosePeriod::InvalidState => error
    redirect_to budget_month_month_close_path(@budget_month), alert: error.message
  end

  private

  def load_context
    @budget_month = current_user.budget_months.find(params[:budget_month_id])
    context = Budgeting::TargetPeriodContext.call(user: current_user, budget_month: @budget_month)
    raise ActiveRecord::RecordNotFound if context.blank?

    @workspace = context.workspace
    @membership = context.membership
    @target_period = context.period
  end
end
