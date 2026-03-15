module Users
  class RegistrationsController < Devise::RegistrationsController
    include TurnstileProtected

    layout "authentication"

    def create
      return render_turnstile_failure unless turnstile_verified?

      super
    end

    private

    def render_turnstile_failure
      build_resource(sign_up_params)
      attach_turnstile_error(resource)
      clean_up_passwords(resource)
      set_minimum_password_length

      render :new, status: :unprocessable_content
    end
  end
end
