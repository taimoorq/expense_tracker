class OperationRunsController < ApplicationController
  before_action :load_operation

  def show
    @status = Platform::Operations::Status.build(@operation)
    render :show, layout: false if request.headers["Turbo-Frame"] == "operation_status_#{@operation.id}"
  end

  private

  def load_operation
    workspace = current_user.legacy_owned_budget_workspace
    raise ActiveRecord::RecordNotFound if workspace.blank?

    workspace.workspace_memberships.status_active.find_by!(user: current_user)
    @operation = workspace.operation_runs.find(params[:id])
    raise ActiveRecord::RecordNotFound unless Platform::Operations::Status.visible_type?(@operation.operation_type)
  end
end
