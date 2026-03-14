class CreateMonthlyBills < ActiveRecord::Migration[8.1]
  def change
    create_table :monthly_bills, id: :uuid do |t|
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.decimal :default_amount, precision: 12, scale: 2
      t.integer :due_day, null: false, default: 1
      t.string :account
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :monthly_bills, :active
    add_index :monthly_bills, :kind
  end
end
