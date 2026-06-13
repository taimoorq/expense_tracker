class AddFinancialRhythmToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :financial_rhythm, :string, null: false, default: "steady_income"
  end
end
