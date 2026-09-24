class AddActivityReviewEvidence < ActiveRecord::Migration[8.1]
  def change
    add_column :financial_transactions, :reviewed_at, :datetime
    add_column :provider_transactions, :resolution_kind, :string, null: false, default: "imported"
    add_check_constraint :provider_transactions, "resolution_kind IN ('imported', 'existing')", name: "provider_transaction_resolution_kind"
  end
end
