module Platform
  module Backup
    class ArchiveCodec
      FORMAT_NAME = "finance_tracking_automatic_backup_encrypted".freeze
      VERSION = 1
      CIPHER = "aes-256-gcm".freeze

      def self.encode(payload:, configuration: ArchiveConfiguration.current, key_id: configuration.primary_key_id)
        raise ArgumentError, configuration.error unless configuration.ready?
        key = configuration.key_for(key_id)
        raise ArgumentError, "The requested backup encryption key is not configured." unless key

        JSON.pretty_generate(
          format: FORMAT_NAME,
          version: VERSION,
          encrypted_at: Time.current.iso8601,
          cipher: CIPHER,
          key_id: key_id,
          payload: encryptor(key).encrypt_and_sign(JSON.pretty_generate(payload))
        )
      end

      def self.decode_envelope(envelope:, configuration: ArchiveConfiguration.current)
        return failure("This automatic backup version is not supported.") unless envelope[:version].to_i == VERSION
        return failure("This automatic backup cipher is not supported.") unless envelope[:cipher] == CIPHER

        key = configuration.key_for(envelope[:key_id])
        return failure("The encryption key required for this automatic backup is not configured.") unless key

        decrypted = encryptor(key).decrypt_and_verify(envelope.fetch(:payload))
        Platform::UserDataBackupCodec.decode(source: decrypted, archive_configuration: configuration)
          .merge(encrypted: true, protection: "installation_key", key_id: envelope[:key_id])
      rescue KeyError, ActiveSupport::MessageEncryptor::InvalidMessage
        failure("The automatic backup is corrupted or its encryption key is incorrect.")
      end

      def self.encryptor(key)
        ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
      end
      private_class_method :encryptor

      def self.failure(message)
        { success: false, error: message }
      end
      private_class_method :failure
    end
  end
end
