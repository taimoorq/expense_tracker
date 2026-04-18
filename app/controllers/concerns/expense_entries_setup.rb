module ExpenseEntriesSetup
  extend ActiveSupport::Concern

  private

  def set_budget_month
    @budget_month = current_user.budget_months.find(params[:budget_month_id])
  end

  def set_expense_entry
    @expense_entry = @budget_month.expense_entries.find(params[:id])
  end

  def expense_entry_params
    params.require(:expense_entry).permit(
      :occurred_on,
      :section,
      :category,
      :payee,
      :planned_amount,
      :actual_amount,
      :source_account_id,
      :account,
      :status,
      :need_or_want,
      :notes
    )
  end

  def planning_template_params
    return ActionController::Parameters.new.permit! unless params[:planning_template].present?

    params.require(:planning_template).permit(
      :enabled,
      :template_type,
      :due_day,
      :cadence,
      :day_of_month_one,
      :day_of_month_two,
      :weekend_adjustment,
      :billing_frequency,
      :kind,
      :total_due,
      :amount_paid,
      billing_months: []
    )
  end
end
