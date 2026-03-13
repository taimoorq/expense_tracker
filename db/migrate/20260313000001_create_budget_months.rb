class CreateBudgetMonths < ActiveRecord::Migration[8.1]
  def change
    create_table :budget_months do |t|
      t.string :label, null: false
      t.date :month_on, null: false
      t.decimal :planned_income, precision: 12, scale: 2
      t.decimal :actual_income, precision: 12, scale: 2
      t.decimal :leftover, precision: 12, scale: 2
      t.text :notes

      t.timestamps
    end

    add_index :budget_months, :month_on, unique: true
  end
end
