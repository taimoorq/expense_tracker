module Admin
  class SessionsController < Devise::SessionsController
    layout "authentication"

    def create
      super do |admin_user|
        AdminAuditLog.create!(
          admin_user: admin_user,
          action: "admin.session.sign_in",
          metadata: {
            request_method: request.request_method,
            path: request.fullpath
          },
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end
    end

    def destroy
      admin_user = current_admin_user

      if admin_user
        AdminAuditLog.create!(
          admin_user: admin_user,
          action: "admin.session.sign_out",
          metadata: {
            request_method: request.request_method,
            path: request.fullpath
          },
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      super
    end
  end
end
