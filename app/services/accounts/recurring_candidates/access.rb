module Accounts
  module RecurringCandidates
    module Access
      def self.authorize!(user:, account:)
        raise ActiveRecord::RecordNotFound unless account.user_id == user.id
        workspace = account.budget_workspace
        return unless workspace

        membership = workspace.workspace_memberships.find_by(user: user)
        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
        Platform::TargetSync::Context.for(account)
      end
    end
  end
end
