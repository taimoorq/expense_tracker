module Users
  class PasswordsController < Devise::PasswordsController
    include DeviseRateLimited
    include TurnstileProtected

    layout "authentication"
    rate_limit_devise_identity to: 5, within: 15.minutes, scope: "devise:user:passwords", name: "identity", only: :create
    rate_limit_devise_ip to: 20, within: 1.hour, scope: "devise:user:passwords", name: "ip", only: :create

    def create
      return render_turnstile_failure unless turnstile_verified?

      super
    end

    private

    def render_turnstile_failure
      self.resource = resource_class.new(password_reset_params)
      attach_turnstile_error(resource)

      render :new, status: :unprocessable_content
    end

    def rate_limit_resource_params
      password_reset_params
    end

    def password_reset_params
      params.fetch(resource_name, {}).permit(:email)
    end
  end
end
