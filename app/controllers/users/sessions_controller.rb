module Users
  class SessionsController < Devise::SessionsController
    include TurnstileProtected

    layout "authentication"

    def create
      return render_turnstile_failure unless turnstile_verified?

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
