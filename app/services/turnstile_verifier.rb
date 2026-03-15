require "json"
require "net/http"

class TurnstileVerifier
  VERIFY_URI = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

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
      request = Net::HTTP::Post.new(VERIFY_URI)
      request.set_form_data(
        "secret" => self.class.secret_key,
        "response" => token,
        "remoteip" => remote_ip
      )

      response = Net::HTTP.start(VERIFY_URI.hostname, VERIFY_URI.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end

      JSON.parse(response.body)
    end
  end
end
