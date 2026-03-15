module Users
  class PasswordsController < Devise::PasswordsController
    include TurnstileProtected

    layout "authentication"

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

    def password_reset_params
      params.fetch(resource_name, {}).permit(:email)
    end
  end
end
