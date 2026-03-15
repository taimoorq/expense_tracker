class UserDataBackupCodec
  ENCRYPTED_FORMAT_NAME = "expense_tracker_backup_encrypted".freeze
  ENCRYPTED_FORMAT_VERSION = 1
  CIPHER = "aes-256-gcm".freeze

  def self.encode(payload:, password: nil)
    plain_json = JSON.pretty_generate(payload)
    return plain_json if password.blank?

    salt = SecureRandom.random_bytes(16)
    encryptor = build_encryptor(password, salt)
    encrypted_payload = encryptor.encrypt_and_sign(plain_json)

    JSON.pretty_generate(
      format: ENCRYPTED_FORMAT_NAME,
      version: ENCRYPTED_FORMAT_VERSION,
      encrypted_at: Time.current.iso8601,
      salt: Base64.strict_encode64(salt),
      payload: encrypted_payload
    )
  end

  def self.decode(source:, password: nil)
    raw_json = source.respond_to?(:read) ? source.read : source.to_s
    parsed = JSON.parse(raw_json).deep_symbolize_keys

    if parsed[:format] == UserDataExport::FORMAT_NAME
      validation = validate_plain_payload(parsed)
      return validation unless validation[:success]

      return success(payload: parsed, encrypted: false)
    end

    unless parsed[:format] == ENCRYPTED_FORMAT_NAME
      return failure("This file is not a supported Expense Tracker backup.")
    end

    unless parsed[:version] == ENCRYPTED_FORMAT_VERSION
      return failure("This encrypted backup version is not supported.")
    end

    if password.blank?
      return failure("This backup is encrypted. Enter the export password to continue.")
    end

    decrypted_json = build_encryptor(password, Base64.strict_decode64(parsed.fetch(:salt))).decrypt_and_verify(parsed.fetch(:payload))
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

  def self.build_encryptor(password, salt)
    key = ActiveSupport::KeyGenerator.new(password).generate_key(salt, ActiveSupport::MessageEncryptor.key_len(CIPHER))
    ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
  end
  private_class_method :build_encryptor

  def self.validate_plain_payload(payload)
    unless payload[:format] == UserDataExport::FORMAT_NAME
      return failure("This file is not a supported Expense Tracker backup.")
    end

    unless payload[:version] == UserDataExport::FORMAT_VERSION
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
