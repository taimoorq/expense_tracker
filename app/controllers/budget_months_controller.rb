class BudgetMonthsController < ApplicationController
  include MonthPageRefresh
  include BudgetMonthFlow

  def index
    auto_complete_due_recurring_entries(current_user.expense_entries)
    apply_index_data(Budgeting::MonthIndexLoader.call(user: current_user, year_param: params[:year]))
  end

  def show
    @budget_month = current_user.budget_months.find(params[:id])
    auto_complete_due_recurring_entries(@budget_month.expense_entries)
    month_data = Budgeting::MonthShowLoader.call(user: current_user, budget_month: @budget_month, expense_entry_loader: method(:preload_month_expense_entries))
    @expense_entries = month_data.expense_entries
    @expense_entry = month_data.expense_entry
    @previous_budget_month = month_data.previous_budget_month
    @next_budget_month = month_data.next_budget_month
  end

  def new
    form_state = load_month_form_state
    @budget_month = current_user.budget_months.new(form_state.new_month_defaults)
  end

  def create
    form_state = load_month_form_state
    result = Budgeting::MonthCreator.call(
      user: current_user,
      budget_month_params: budget_month_params,
      month_workflow: form_state.month_workflow,
      source_budget_month: form_state.source_budget_month,
      include_applicable_templates: form_state.include_applicable_templates
    )
    @budget_month = result.budget_month
    return redirect_to @budget_month, notice: result.notice if result.success?

    @wizard_step = result.wizard_step
    render :new, status: :unprocessable_entity
  end

  def generate_paychecks
    run_generation(:paychecks)
  end

  def generate_subscriptions
    run_generation(:subscriptions)
  end

  def generate_monthly_bills
    run_generation(:monthly_bills)
  end

  def generate_payment_plans
    run_generation(:payment_plans)
  end

  def estimate_credit_cards
    run_generation(:credit_cards)
  end

  private

  def budget_month_params
    params.require(:budget_month).permit(:label, :month_on, :leftover, :notes)
  end
end
