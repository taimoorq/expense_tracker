class CreateAccountRecurringCandidateDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :account_recurring_candidate_decisions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :budget_workspace, type: :uuid, foreign_key: true
      t.references :subscription, type: :uuid, foreign_key: true
      t.references :monthly_bill, type: :uuid, foreign_key: true
      t.integer :key_version, null: false, default: 1
      t.string :merchant_key, null: false
      t.string :status, null: false, default: "unreviewed"
      t.jsonb :evidence_summary, null: false, default: {}
      t.string :request_digest
      t.datetime :reviewed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.index [ :account_id, :key_version, :merchant_key ], unique: true, name: "recurring_candidate_identity"
      t.check_constraint "key_version = 1 AND merchant_key ~ '^[0-9a-f]{64}$'", name: "recurring_candidate_key"
      t.check_constraint "(status = 'linked' AND num_nonnulls(subscription_id, monthly_bill_id) = 1) OR (status IN ('unreviewed', 'ignored') AND num_nonnulls(subscription_id, monthly_bill_id) = 0)", name: "recurring_candidate_resolution"
    end
  end
end
