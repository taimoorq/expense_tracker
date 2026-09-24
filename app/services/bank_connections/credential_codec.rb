module BankConnections
  module CredentialCodec
    module_function

    def encode(value)
      encryptor.encrypt_and_sign(value, purpose: "simplefin")
    end

    def decode(value)
      encryptor.decrypt_and_verify(value, purpose: "simplefin")
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      raise ArgumentError, "The saved connection cannot be decrypted. Reconnect SimpleFIN."
    end

    def fingerprint(value)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("simplefin-fingerprint", 32), value)
    end

    def encryptor
      key = Rails.application.key_generator.generate_key("simplefin-credentials-v1", 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
    end
  end
end
