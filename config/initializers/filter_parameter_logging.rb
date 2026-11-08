# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :payload, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :access_url, :claim_url, :authorization, :claim_fingerprint
]

Rails.application.config.filter_parameters += %i[candidate_template template_token evidence_digest preview_digest]

# Database bind logging uses Active Record's filter, which may be initialized
# before the application parameter filters. Avoid inspecting entire import and
# backup graphs again just to format a debug SQL line.
ActiveSupport.on_load(:active_record) do
  self.filter_attributes += %i[payload encrypted_contents encrypted_export_password previous_revisions]
end
