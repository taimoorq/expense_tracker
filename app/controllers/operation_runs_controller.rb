class OperationRunsController < ApplicationController
  before_action :load_operation

  def show
    @status = Platform::Operations::Status.build(@operation)
    @backup_export_artifact = current_user.backup_export_artifacts.available.find_by(operation_run: @operation)
    @backup_archive = @operation.budget_workspace.backup_archives.state_ready.find_by(operation_run: @operation)
    render :show, layout: false if request.headers["Turbo-Frame"] == "operation_status_#{@operation.id}"
  end

  private

  def load_operation
    workspace = current_user.legacy_owned_budget_workspace
    raise ActiveRecord::RecordNotFound if workspace.blank?

    membership = workspace.workspace_memberships.status_active.find_by!(user: current_user)
    @operation = workspace.operation_runs.find(params[:id])
    raise ActiveRecord::RecordNotFound unless Platform::Operations::Status.visible_type?(@operation.operation_type)
    if Platform::Operations::Status.automatic_backup_type?(@operation.operation_type) && !membership.role_owner?
      raise ActiveRecord::RecordNotFound
    end
  end
end
