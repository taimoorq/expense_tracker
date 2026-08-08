module Platform
  class UserDataImport
    SCOPES = Platform::UserDataExport::SCOPES

    def initialize(user:, payload:, scopes:, replace_existing: false, checkpoint: nil, rollback: false)
      @user = user
      @payload = payload.to_h.deep_symbolize_keys
      @scopes = Array(scopes).map(&:to_s) & SCOPES
      @replace_existing = replace_existing
      @checkpoint = checkpoint
      @rollback = rollback
    end

    def call
      validation = validate_payload
      return validation if validation

      Platform::Backup::RestoreCoordinator.call(
        user: user,
        payload: payload,
        scopes: scopes,
        replace_existing: replace_existing,
        checkpoint: checkpoint,
        rollback: rollback
      )
    end

    private

    attr_reader :checkpoint, :payload, :replace_existing, :rollback, :scopes, :user

    def validate_payload
      unless payload[:format] == Platform::UserDataExport::FORMAT_NAME
        return failure("This file is not a supported FinanceTracking.app backup.")
      end

      return if payload[:version].to_i.in?([ 1, 2 ])

      failure("This backup version is not supported.")
    end

    def failure(message)
      { success: false, error: message }
    end
  end
end
