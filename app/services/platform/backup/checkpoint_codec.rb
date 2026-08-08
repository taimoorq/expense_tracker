module Platform
  module Backup
    class CheckpointCodec
      VERSION = "app-key-v1".freeze
      CIPHER = "aes-256-gcm".freeze
      SALT = "finance-tracking-restore-checkpoint-v1".freeze

      def self.encode(payload)
        encryptor.encrypt_and_sign(Platform::CanonicalJson.dump(payload))
      end

      def self.decode(ciphertext)
        JSON.parse(encryptor.decrypt_and_verify(ciphertext)).deep_symbolize_keys
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError
        raise InvalidCheckpoint, "The restore checkpoint cannot be decrypted or is corrupted."
      end

      def self.encryptor
        key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(SALT, 32)
        ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
      end
      private_class_method :encryptor

      class InvalidCheckpoint < StandardError; end
    end
  end
end
