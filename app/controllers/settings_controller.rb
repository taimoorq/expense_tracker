class SettingsController < ApplicationController
  def show; end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.require(:user).permit(:default_landing_page, :preferred_month_view)
  end
end
