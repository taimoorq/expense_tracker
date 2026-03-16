class RemovePlannedAndActualIncomeFromBudgetMonths < ActiveRecord::Migration[8.1]
  def change
    remove_column :budget_months, :planned_income, :decimal
    remove_column :budget_months, :actual_income, :decimal
  end
end
