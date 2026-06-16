require "openssl"

module DeviseRateLimited
  extend ActiveSupport::Concern

  RATE_LIMIT_MESSAGE = "Too many requests. Please wait a few minutes and try again."

  class << self
    def store
      @store ||= Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : ActionController::Base.cache_store || Rails.cache
    end

    def clear_store
      store.clear if store.respond_to?(:clear)
    end

    def email_digest_secret
      @email_digest_secret ||= Rails.application.key_generator.generate_key("devise-rate-limit-email", 32)
    end
  end

  class_methods do
    def rate_limit_devise_identity(to:, within:, scope:, name:, **options)
      rate_limit to: to,
        within: within,
        by: :devise_rate_limit_identity,
        with: :render_rate_limit_failure,
        store: DeviseRateLimited.store,
        scope: scope,
        name: name,
        **options
    end

    def rate_limit_devise_ip(to:, within:, scope:, name:, **options)
      rate_limit to: to,
        within: within,
        by: :devise_rate_limit_ip,
        with: :render_rate_limit_failure,
        store: DeviseRateLimited.store,
        scope: scope,
        name: name,
        **options
    end
  end

  private

  def devise_rate_limit_ip
    request.remote_ip.to_s
  end

  def devise_rate_limit_identity
    "#{devise_rate_limit_ip}:#{devise_rate_limit_email_digest}"
  end

  def devise_rate_limit_email_digest
    email = params.fetch(resource_name, {})[:email].to_s.strip.downcase
    return "blank" if email.blank?

    OpenSSL::HMAC.hexdigest("SHA256", DeviseRateLimited.email_digest_secret, email)
  end

  def render_rate_limit_failure
    prepare_rate_limited_resource
    resource.errors.add(:base, RATE_LIMIT_MESSAGE)
    clean_up_passwords(resource) if respond_to?(:clean_up_passwords, true)

    render :new, status: :too_many_requests
  end

  def prepare_rate_limited_resource
    self.resource = resource_class.new(rate_limit_resource_params)
  end

  def rate_limit_resource_params
    params.fetch(resource_name, {}).permit(:email)
  end
end
