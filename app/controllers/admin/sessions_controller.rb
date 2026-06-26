module Admin
  class SessionsController < Devise::SessionsController
    include DeviseRateLimited
    include TurnstileProtected

    layout "authentication"
    rate_limit_devise_identity to: 5, within: 5.minutes, scope: "devise:admin:sessions", name: "identity", only: :create
    rate_limit_devise_ip to: 15, within: 5.minutes, scope: "devise:admin:sessions", name: "ip", only: :create

    def create
      return render_turnstile_failure unless turnstile_verified?

      super { |admin_user| audit_admin_session(admin_user, "admin.session.sign_in") }
    end

    def destroy
      audit_admin_session(current_admin_user, "admin.session.sign_out")

      super
    end

    private

    def audit_admin_session(admin_user, action)
      return if admin_user.blank?

      AdminAuditLog.create!(
        admin_user: admin_user,
        action: action,
        metadata: audit_request_metadata,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def audit_request_metadata
      {
        request_method: request.request_method,
        path: request.fullpath
      }
    end

    def rate_limit_resource_params
      sign_in_params
    end

    def render_turnstile_failure
      self.resource = resource_class.new(sign_in_params)
      attach_turnstile_error(resource)
      clean_up_passwords(resource)

      render :new, status: :unprocessable_content
    end
  end
end
