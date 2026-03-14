module Admin
  class DashboardController < BaseController
    def show
      @active_users_count = User.access_state_active.count
      @suspended_users_count = User.access_state_suspended.count
      @recent_audit_logs = AdminAuditLog.includes(:admin_user, :target_user).recent_first.limit(10)

      set_admin_audit_context(action: "admin.dashboard.view")
    end
  end
end
