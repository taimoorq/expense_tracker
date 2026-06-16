module Users
  class SessionsController < Devise::SessionsController
    include DeviseRateLimited
    include TurnstileProtected

    layout "authentication"
    rate_limit_devise_identity to: 5, within: 5.minutes, scope: "devise:user:sessions", name: "identity", only: :create
    rate_limit_devise_ip to: 25, within: 5.minutes, scope: "devise:user:sessions", name: "ip", only: :create

    def create
      return render_turnstile_failure unless turnstile_verified?

      super
    end

    private

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
