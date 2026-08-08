class MigrationDiscrepancyResolutionsController < ApplicationController
  def update
    workspace = current_user.legacy_owned_budget_workspace || raise(ActiveRecord::RecordNotFound)
    membership = workspace.workspace_memberships.status_active.find_by!(user: current_user)
    discrepancy = workspace.migration_discrepancies.find(params[:id])
    account = current_user.accounts.find(params.require(:account_id))

    Platform::TargetBackfill::ResolveMissingAccount.call(
      workspace: workspace,
      actor_membership: membership,
      discrepancy: discrepancy,
      account: account
    )

    redirect_to activity_path(view: "review"), notice: "Account connected. Migration checks were run again."
  rescue Platform::TargetBackfill::ResolveMissingAccount::InvalidState,
    Identity::WorkspaceAccess::NotAuthorized,
    ActiveRecord::RecordInvalid => error
    redirect_to activity_path(view: "review"), alert: error.message
  end
end
