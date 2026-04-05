# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.font_src :self, :https, :data
    policy.form_action :self
    policy.frame_ancestors :none
    policy.frame_src :self, "https://challenges.cloudflare.com"
    policy.img_src :self, :https, :data, :blob
    policy.manifest_src :self
    policy.object_src :none
    policy.script_src :self, "https://cdn.jsdelivr.net", "https://challenges.cloudflare.com"
    policy.script_src_attr :none
    policy.connect_src :self, "https://challenges.cloudflare.com"
    policy.style_src :self, :https
    policy.style_src_attr :unsafe_inline
    policy.worker_src :self

    policy.upgrade_insecure_requests unless Rails.env.development? || Rails.env.test?
  end

  # Importmap and CDN-backed script tags render inline bootstrap scripts, so
  # attach a per-request nonce and let Rails add it to supported helpers.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w(script-src)
  config.content_security_policy_nonce_auto = true
end
