class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.string :name, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.integer :due_day, null: false, default: 1
      t.string :account
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :subscriptions, :active
  end
end
