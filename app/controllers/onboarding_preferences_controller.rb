class OnboardingPreferencesController < ApplicationController
  def update
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    membership = provisioned.membership
    Identity::WorkspaceAccess.authorize_write!(workspace: provisioned.workspace, membership: membership)
    attributes = { onboarding_version: Overview::OnboardingProgress::VERSION }
    attributes[:onboarding_dismissed_at] = dismissed? ? Time.current : nil if params.key?(:dismissed)
    attributes[:onboarding_path] = params[:path] if params.key?(:path)
    attributes[:onboarding_recurring_skipped_at] = Time.current if params[:skip] == "recurring"
    attributes[:onboarding_balance_deferred_at] = Time.current if params[:skip] == "balance"
    if params[:reviewed] == "1"
      raise ArgumentError, "Create a month before completing your first review." unless current_user.budget_months.exists?
      attributes[:onboarding_reviewed_at] = Time.current
    end
    membership.update!(attributes)

    if params[:start] == "1"
      destination = case membership.onboarding_path
      when "simplefin" then new_bank_connection_path
      when "import" then activity_import_path
      else new_account_path
      end
      return redirect_to destination, status: :see_other
    end

    redirect_back fallback_location: root_path,
      notice: dismissed? ? "Setup checklist hidden. You can show it again from Settings." : "Setup preferences saved.", status: :see_other
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to root_path, alert: error.message, status: :see_other
  end

  private

  def dismissed?
    ActiveModel::Type::Boolean.new.cast(params[:dismissed])
  end
end
