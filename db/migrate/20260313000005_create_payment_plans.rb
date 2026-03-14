class CreatePaymentPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_plans, id: :uuid do |t|
      t.string :name, null: false
      t.decimal :total_due, precision: 12, scale: 2, null: false
      t.decimal :amount_paid, precision: 12, scale: 2, null: false, default: 0
      t.decimal :monthly_target, precision: 12, scale: 2
      t.integer :due_day, null: false, default: 15
      t.string :account
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :payment_plans, :active
  end
end
