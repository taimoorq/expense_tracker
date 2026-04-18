class BudgetMonthsController < ApplicationController
  include MonthPageRefresh

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

  def load_month_form_state
    form_state = Budgeting::MonthFormState.call(user: current_user, params: params)
    apply_form_state(form_state)
    form_state
  end

  def handle_month_generation(budget_month, message)
    respond_to do |format|
      format.turbo_stream do
        prepare_month_refresh_state(budget_month, expense_entry: budget_month.expense_entries.new, auto_complete_recurring: true)
        render_month_page_refresh(message: message, include_entry_form: true)
      end
      format.html { redirect_to budget_month, notice: message }
    end
  end

  def budget_month_params
    params.require(:budget_month).permit(:label, :month_on, :leftover, :notes)
  end

  def apply_index_data(index_data)
    @budget_months = index_data.budget_months
    @selected_year = index_data.selected_year
    @previous_years = index_data.previous_years
    @visible_budget_months = index_data.visible_budget_months
    @planning_template_counts = index_data.planning_template_counts
  end

  def apply_form_state(form_state)
    @cloneable_budget_months = form_state.cloneable_budget_months
    @cloneable_month_options = form_state.cloneable_month_options
    @source_budget_month = form_state.source_budget_month
    @clone_preview = form_state.clone_preview
    @month_workflow = form_state.month_workflow
    @wizard_step = form_state.wizard_step
    @include_applicable_templates = form_state.include_applicable_templates
  end

  def run_generation(action)
    result = Recurring::MonthGenerationRunner.call(user: current_user, budget_month_id: params[:id], action: action)
    handle_month_generation(result.budget_month, result.message)
  end
end
