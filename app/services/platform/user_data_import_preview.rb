module Platform
  class UserDataImportPreview
    SCOPES = Platform::UserDataExport::SCOPES

    def initialize(payload:, scopes:)
      @payload = payload.to_h.deep_symbolize_keys
      @scopes = Array(scopes).map(&:to_s) & SCOPES
    end

    def call
      adapter = adapter_for_payload
      return adapter if adapter.is_a?(Hash)

      adapter.call
    end

    private

    attr_reader :payload, :scopes

    def adapter_for_payload
      unless payload[:format] == Platform::UserDataExport::FORMAT_NAME
        return failure("This file is not a supported Expense Tracker backup.")
      end

      case payload[:version].to_i
      when 1
        Platform::Backup::V1::Preview.new(payload: payload, scopes: scopes)
      else
        failure("This backup version is not supported.")
      end
    end

    def failure(message)
      { success: false, error: message }
    end
  end
end
