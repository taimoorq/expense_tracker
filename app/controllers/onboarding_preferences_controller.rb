class OnboardingPreferencesController < ApplicationController
  def update
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    membership = provisioned.membership
    membership.update!(
      onboarding_version: Overview::OnboardingProgress::VERSION,
      onboarding_dismissed_at: dismissed? ? Time.current : nil
    )

    redirect_back fallback_location: root_path,
      notice: dismissed? ? "Setup checklist hidden. You can show it again from Settings." : "Setup checklist restored."
  end

  private

  def dismissed?
    ActiveModel::Type::Boolean.new.cast(params[:dismissed])
  end
end
