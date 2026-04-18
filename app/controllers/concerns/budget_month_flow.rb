module BudgetMonthFlow
  extend ActiveSupport::Concern

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
