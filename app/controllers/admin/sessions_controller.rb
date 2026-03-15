module Admin
  class SessionsController < Devise::SessionsController
    include TurnstileProtected

    layout "authentication"

    def create
      return render_turnstile_failure unless turnstile_verified?

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

    private

    def render_turnstile_failure
      self.resource = resource_class.new(sign_in_params)
      attach_turnstile_error(resource)
      clean_up_passwords(resource)

      render :new, status: :unprocessable_content
    end
  end
end
