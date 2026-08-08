class AddMigrationResolutionAuditAction < ActiveRecord::Migration[8.1]
  ORIGINAL_ACTIONS = %w[
    create edit void reverse archive import import_reversal match unmatch generate
    trust_observation supersede_observation close reopen backup_export backup_restore
    access_change
  ].freeze
  NEW_ACTIONS = (ORIGINAL_ACTIONS + [ "resolve_migration_discrepancy" ]).freeze

  def up
    replace_constraint(NEW_ACTIONS)
  end

  def down
    replace_constraint(ORIGINAL_ACTIONS)
  end

  private

  def replace_constraint(actions)
    remove_check_constraint :audit_events, name: "audit_events_action_valid"
    add_check_constraint :audit_events,
      "action IN (#{actions.map { |action| connection.quote(action) }.join(', ')})",
      name: "audit_events_action_valid"
  end
end
