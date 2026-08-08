class SettingsController < ApplicationController
  def show
    @onboarding_membership = Identity::PersonalWorkspaceProvisioner.call(user: current_user).membership
  end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      @onboarding_membership = Identity::PersonalWorkspaceProvisioner.call(user: current_user).membership
      render :show, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.require(:user).permit(:default_landing_page, :preferred_month_view, :financial_rhythm)
  end
end
