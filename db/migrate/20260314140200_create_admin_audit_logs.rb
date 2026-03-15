class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_logs, id: :uuid do |t|
      t.references :admin_user, null: false, foreign_key: true, type: :uuid
      t.references :target_user, foreign_key: { to_table: :users }, type: :uuid
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :admin_audit_logs, :action
    add_index :admin_audit_logs, :created_at
  end
end
