module Users
  class RegistrationsController < Devise::RegistrationsController
    include DeviseRateLimited
    include TurnstileProtected

    layout "authentication"
    before_action :configure_sign_up_params, only: :create
    rate_limit_devise_ip to: 5, within: 1.hour, scope: "devise:user:registrations", name: "ip", only: :create

    def create
      return render_turnstile_failure unless turnstile_verified?

      super
    end

    private

    def configure_sign_up_params
      devise_parameter_sanitizer.permit(:sign_up, keys: [ :financial_rhythm ])
    end

    def prepare_rate_limited_resource
      build_resource(sign_up_params)
      set_minimum_password_length
    end

    def render_turnstile_failure
      build_resource(sign_up_params)
      attach_turnstile_error(resource)
      clean_up_passwords(resource)
      set_minimum_password_length

      render :new, status: :unprocessable_content
    end
  end
end
