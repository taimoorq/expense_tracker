class RecentOperationsPreferencesController < ApplicationController
  def update
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    provisioned.membership.update!(recent_operations_dismissed_through_at: Time.current)

    redirect_to root_path,
      notice: "Completed operation status dismissed. New activity will appear here.",
      status: :see_other
  end
end
