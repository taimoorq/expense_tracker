module Platform
  class UserDataBackupCodec
    ENCRYPTED_FORMAT_NAME = "expense_tracker_backup_encrypted".freeze
    ENCRYPTED_FORMAT_VERSION = 2
    LEGACY_ENCRYPTED_FORMAT_VERSION = 1
    CIPHER = "aes-256-gcm".freeze
    KDF_ALGORITHM = "pbkdf2-hmac".freeze
    KDF_DIGEST = "sha256".freeze
    KDF_ITERATIONS = 210_000
    SALT_BYTES = 16
    SUPPORTED_PAYLOAD_VERSIONS = [ 1, 2 ].freeze

    def self.encode(payload:, password: nil)
      plain_json = JSON.pretty_generate(payload)
      return plain_json if password.blank?

      salt = SecureRandom.random_bytes(SALT_BYTES)
      encryptor = build_encryptor(password, salt, digest: KDF_DIGEST, iterations: KDF_ITERATIONS)
      encrypted_payload = encryptor.encrypt_and_sign(plain_json)

      JSON.pretty_generate(
        format: ENCRYPTED_FORMAT_NAME,
        version: ENCRYPTED_FORMAT_VERSION,
        encrypted_at: Time.current.iso8601,
        cipher: CIPHER,
        kdf: {
          algorithm: KDF_ALGORITHM,
          digest: KDF_DIGEST,
          iterations: KDF_ITERATIONS,
          salt: Base64.strict_encode64(salt)
        },
        payload: encrypted_payload
      )
    end

    def self.decode(source:, password: nil)
      raw_json = source.respond_to?(:read) ? source.read : source.to_s
      parsed = JSON.parse(raw_json).deep_symbolize_keys

      if parsed[:format] == Platform::UserDataExport::FORMAT_NAME
        validation = validate_plain_payload(parsed)
        return validation unless validation[:success]

        return success(payload: parsed, encrypted: false)
      end

      unless parsed[:format] == ENCRYPTED_FORMAT_NAME
        return failure("This file is not a supported FinanceTracking.app backup.")
      end

      unless parsed[:version].in?([ LEGACY_ENCRYPTED_FORMAT_VERSION, ENCRYPTED_FORMAT_VERSION ])
        return failure("This encrypted backup version is not supported.")
      end

      if password.blank?
        return failure("This backup is encrypted. Enter the export password to continue.")
      end

      decrypted_json = decryptor_for(parsed, password).decrypt_and_verify(parsed.fetch(:payload))
      payload = JSON.parse(decrypted_json).deep_symbolize_keys
      validation = validate_plain_payload(payload)
      return validation unless validation[:success]

      success(payload: payload, encrypted: true)
    rescue JSON::ParserError
      failure("The uploaded file is not valid JSON.")
    rescue ArgumentError, ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
      failure("The backup password is incorrect or the file is corrupted.")
    ensure
      source.rewind if source.respond_to?(:rewind)
    end

    def self.decryptor_for(envelope, password)
      if envelope[:version] == LEGACY_ENCRYPTED_FORMAT_VERSION
        key = ActiveSupport::KeyGenerator.new(password).generate_key(
          Base64.strict_decode64(envelope.fetch(:salt)),
          ActiveSupport::MessageEncryptor.key_len(CIPHER)
        )
        return ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
      end

      kdf = envelope.fetch(:kdf)
      raise ArgumentError unless envelope[:cipher] == CIPHER
      raise ArgumentError unless kdf[:algorithm] == KDF_ALGORITHM
      raise ArgumentError unless kdf[:digest] == KDF_DIGEST
      raise ArgumentError unless kdf[:iterations].to_i == KDF_ITERATIONS

      build_encryptor(
        password,
        Base64.strict_decode64(kdf.fetch(:salt)),
        digest: kdf.fetch(:digest),
        iterations: kdf.fetch(:iterations).to_i
      )
    end
    private_class_method :decryptor_for

    def self.build_encryptor(password, salt, digest:, iterations:)
      key = OpenSSL::PKCS5.pbkdf2_hmac(
        password,
        salt,
        iterations,
        ActiveSupport::MessageEncryptor.key_len(CIPHER),
        digest
      )
      ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
    end
    private_class_method :build_encryptor

    def self.validate_plain_payload(payload)
      unless payload[:format] == Platform::UserDataExport::FORMAT_NAME
        return failure("This file is not a supported FinanceTracking.app backup.")
      end

      unless payload[:version].to_i.in?(SUPPORTED_PAYLOAD_VERSIONS)
        return failure("This backup version is not supported.")
      end

      success(payload: payload, encrypted: false)
    end
    private_class_method :validate_plain_payload

    def self.success(payload:, encrypted:)
      { success: true, payload: payload, encrypted: encrypted }
    end
    private_class_method :success

    def self.failure(message)
      { success: false, error: message }
    end
    private_class_method :failure
  end
end
