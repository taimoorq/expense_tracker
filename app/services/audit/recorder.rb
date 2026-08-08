module Audit
  class Recorder
    def self.call(workspace:, actor_membership:, operation_run:, entity:, action:, changed_fields: [])
      AuditEvent.create!(
        budget_workspace: workspace,
        actor_membership: actor_membership,
        actor_user: actor_membership&.user,
        operation_run: operation_run,
        entity_type: entity.class.name,
        entity_id: entity.id,
        action: action,
        changed_fields: { "fields" => Array(changed_fields).map(&:to_s).sort },
        event_at: Time.current
      )
    end
  end
end
