module TurnstileProtected
  extend ActiveSupport::Concern

  private

  def turnstile_verified?
    TurnstileVerifier.new(
      token: params["cf-turnstile-response"],
      remote_ip: request.remote_ip
    ).success?
  end

  def attach_turnstile_error(resource)
    resource.errors.add(:base, "Please complete the verification challenge and try again.")
  end
end
