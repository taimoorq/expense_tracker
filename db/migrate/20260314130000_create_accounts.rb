class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :institution_name
      t.integer :kind, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :include_in_net_worth, null: false, default: true
      t.boolean :include_in_cash, null: false, default: false
      t.text :notes

      t.timestamps
    end

    add_index :accounts, [ :user_id, :name ], unique: true
    add_index :accounts, :kind
    add_index :accounts, :active
  end
end