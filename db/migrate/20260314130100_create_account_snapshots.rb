class CreateAccountSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :account_snapshots, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.date :recorded_on, null: false
      t.decimal :balance, precision: 14, scale: 2, null: false
      t.decimal :available_balance, precision: 14, scale: 2
      t.text :notes

      t.timestamps
    end

    add_index :account_snapshots, [ :account_id, :recorded_on ], unique: true
    add_index :account_snapshots, :recorded_on
  end
end
