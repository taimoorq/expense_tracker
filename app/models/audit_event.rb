class AuditEvent < ApplicationRecord
  ACTIONS = %w[
    create edit void reverse archive import import_reversal match unmatch generate
    trust_observation supersede_observation close reopen backup_export backup_restore
    access_change resolve_migration_discrepancy restore_checkpoint restore_rollback
  ].freeze

  belongs_to :budget_workspace
  belongs_to :actor_membership, class_name: "WorkspaceMembership", optional: true
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :actor_admin_user, class_name: "AdminUser", optional: true
  belongs_to :operation_run, optional: true

  validates :entity_type, :entity_id, :event_at, presence: true
  validates :action, inclusion: { in: ACTIONS }

  def readonly?
    persisted?
  end
end
