class TellerConfiguration
  class << self
    def enabled?
      application_id.present? && certificate_path.present? && private_key_path.present?
    end

    def application_id
      ENV["TELLER_APPLICATION_ID"].to_s.strip.presence
    end

    def environment
      ENV.fetch("TELLER_ENVIRONMENT", "sandbox").to_s.strip.presence || "sandbox"
    end

    def certificate_path
      ENV["TELLER_CERT_PATH"].to_s.strip.presence
    end

    def private_key_path
      ENV["TELLER_KEY_PATH"].to_s.strip.presence
    end

    def connect_js_url
      "https://cdn.teller.io/connect/connect.js"
    end

    def status_label
      enabled? ? "Enabled" : "Disabled"
    end
  end
end
