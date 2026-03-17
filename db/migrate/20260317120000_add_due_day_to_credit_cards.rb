class AddDueDayToCreditCards < ActiveRecord::Migration[8.1]
  def change
    add_column :credit_cards, :due_day, :integer, null: false, default: 1
    add_index :credit_cards, :due_day
  end
end
