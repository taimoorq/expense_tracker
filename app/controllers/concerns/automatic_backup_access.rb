module AutomaticBackupAccess
  extend ActiveSupport::Concern

  private

  def automatic_backup_workspace!
    workspace = current_user.legacy_owned_budget_workspace
    raise ActiveRecord::RecordNotFound unless workspace

    @automatic_backup_membership = workspace.workspace_memberships.status_active.role_owner.find_by!(user: current_user)
    workspace
  end
end
