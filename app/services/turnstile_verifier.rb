require "json"
require "net/http"

class TurnstileVerifier
  VERIFY_URI = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")
  HTTP_TIMEOUT_SECONDS = 5

  def self.enabled?
    site_key.present? && secret_key.present?
  end

  def self.site_key
    ENV["TURNSTILE_SITE_KEY"].presence
  end

  def self.secret_key
    ENV["TURNSTILE_SECRET_KEY"].presence
  end

  def initialize(token:, remote_ip: nil)
    @token = token.to_s
    @remote_ip = remote_ip
  end

  def success?
    return true unless self.class.enabled?
    return false if token.blank?

    payload.fetch("success", false)
  rescue StandardError => error
    Rails.logger.warn("Turnstile verification failed: #{error.class}: #{error.message}")
    false
  end

  private

  attr_reader :token, :remote_ip

  def payload
    @payload ||= begin
      JSON.parse(verification_response.body)
    end
  end

  def verification_response
    # Turnstile tokens are validated on the current auth request and are not reusable,
    # so async processing or caching would weaken the verification step.
    Net::HTTP.start(
      VERIFY_URI.hostname,
      VERIFY_URI.port,
      use_ssl: true,
      open_timeout: HTTP_TIMEOUT_SECONDS,
      read_timeout: HTTP_TIMEOUT_SECONDS
    ) do |http|
      http.request(verification_request)
    end
  end

  def verification_request
    Net::HTTP::Post.new(VERIFY_URI).tap do |request|
      request.set_form_data(
        "secret" => self.class.secret_key,
        "response" => token,
        "remoteip" => remote_ip
      )
    end
  end
end
