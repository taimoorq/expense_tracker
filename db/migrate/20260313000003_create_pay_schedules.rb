class CreatePaySchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :pay_schedules, id: :uuid do |t|
      t.string :name, null: false
      t.integer :cadence, null: false, default: 2
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.date :first_pay_on, null: false
      t.integer :day_of_month_one
      t.integer :day_of_month_two
      t.integer :weekend_adjustment, null: false, default: 1
      t.string :account
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :pay_schedules, :active
    add_index :pay_schedules, :cadence
  end
end
