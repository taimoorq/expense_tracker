class SettingsController < ApplicationController
  before_action :load_workspace

  def show
  end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      render :show, status: :unprocessable_content
    end
  end

  def workspace
    Identity::WorkspaceAccess.authorize_write!(workspace: @workspace, membership: @onboarding_membership)
    if @workspace.update(params.require(:workspace).permit(:time_zone))
      redirect_to settings_path(anchor: "workspace"), notice: "Workspace timezone updated. Saved explicit times keep their original timezone.", status: :see_other
    else
      render :show, status: :unprocessable_content
    end
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end

  private

  def load_workspace
    context = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    @workspace, @onboarding_membership = context.workspace, context.membership
  end

  def settings_params
    params.require(:user).permit(:default_landing_page, :preferred_month_view, :financial_rhythm)
  end
end
