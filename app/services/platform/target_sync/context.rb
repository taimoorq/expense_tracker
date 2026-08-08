module Platform
  module TargetSync
    class Context
      Result = Data.define(:workspace, :membership)

      def self.for(record)
        user = record.respond_to?(:user) ? record.user : nil
        workspace = record.try(:budget_workspace)
        workspace ||= BudgetWorkspace.find_by(legacy_owner_user_id: user&.id)
        return if workspace.blank? || !workspace.target_writes_enabled?

        unless workspace.target_backfilled_at.present? && workspace.target_backfill_version == TargetBackfill::WorkspaceBootstrap::VERSION
          raise IncompleteBackfill, "Target writes require a verified target backfill"
        end

        membership = workspace.workspace_memberships.status_active.find_by!(user: user)
        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
        Result.new(workspace: workspace, membership: membership)
      end

      class IncompleteBackfill < StandardError; end
    end
  end
end
