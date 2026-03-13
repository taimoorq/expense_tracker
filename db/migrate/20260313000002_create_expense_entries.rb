class CreateExpenseEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :expense_entries do |t|
      t.references :budget_month, null: false, foreign_key: true
      t.date :occurred_on
      t.integer :section, null: false, default: 6
      t.string :category
      t.string :payee
      t.decimal :planned_amount, precision: 12, scale: 2
      t.decimal :actual_amount, precision: 12, scale: 2
      t.string :account
      t.integer :status, null: false, default: 0
      t.string :need_or_want
      t.text :notes
      t.string :source_file

      t.timestamps
    end

    add_index :expense_entries, :section
    add_index :expense_entries, :status
    add_index :expense_entries, :occurred_on
  end
end
