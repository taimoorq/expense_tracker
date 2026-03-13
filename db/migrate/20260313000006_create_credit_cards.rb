class CreateCreditCards < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_cards do |t|
      t.string :name, null: false
      t.decimal :minimum_payment, precision: 12, scale: 2, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.string :account
      t.boolean :active, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :credit_cards, :active
    add_index :credit_cards, :priority
  end
end
