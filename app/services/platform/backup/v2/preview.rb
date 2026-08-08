require "digest"

module Platform
  module Backup
    module V2
      class Preview
        SCOPES = Platform::UserDataExport::SCOPES
        FINANCIAL_SCOPES = %w[accounts planning_templates budget_months account_activity].freeze

        def initialize(payload:, scopes:)
          @payload = payload.to_h.deep_symbolize_keys
          @scopes = Array(scopes).map(&:to_s) & SCOPES
        end

        def call
          return failure("Choose at least one section to import.") if scopes.empty?
          return failure("The backup checksum does not match its contents.") unless checksum_valid?

          data = payload.fetch(:data, {})
          missing_scope = scopes.find { |scope| !data.key?(scope.to_sym) }
          return failure("The backup file does not include #{missing_scope.humanize.downcase}.") if missing_scope

          selected_financial_scopes = scopes & FINANCIAL_SCOPES
          if selected_financial_scopes.any? && selected_financial_scopes != FINANCIAL_SCOPES
            return failure("Backup V2 restores the financial sections together so relationships remain complete.")
          end

          {
            success: true,
            summary: {
              sample_backup: false,
              sample_notice: nil,
              exported_at: payload[:exported_at],
              file_scopes: Array(payload[:scopes]),
              selected_scopes: scopes,
              planning_templates: planning_template_summary(data[:planning_templates]),
              budget_months: budget_month_summary(data[:budget_months]),
              accounts: account_summary(data[:accounts]),
              account_activity: account_activity_summary(data[:account_activity]),
              preferences: preference_summary(data[:preferences]),
              payload_checksum: payload[:payload_checksum],
              calculation_version: payload.dig(:workspace, :calculation_version)
            }
          }
        end

        private

        attr_reader :payload, :scopes

        def checksum_valid?
          supplied = payload[:payload_checksum].to_s
          return false unless supplied.match?(/\A[0-9a-f]{64}\z/)

          unsigned = payload.except(:payload_checksum)
          expected = Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(unsigned))
          ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
        end

        def planning_template_summary(data)
          return unless scopes.include?("planning_templates")

          { total: Array(data&.dig(:records)).size, counts: {} }
        end

        def budget_month_summary(data)
          return unless scopes.include?("budget_months")

          {
            months: Array(data&.dig(:periods)).size,
            entries: Array(data&.dig(:items)).size
          }
        end

        def account_summary(data)
          return unless scopes.include?("accounts")

          {
            accounts: Array(data&.dig(:records)).size,
            snapshots: Array(data&.dig(:balance_observations)).size
          }
        end

        def account_activity_summary(data)
          return unless scopes.include?("account_activity")

          {
            imports: Array(data&.dig(:import_batches)).size,
            rows: Array(data&.dig(:import_rows)).size
          }
        end

        def preference_summary(data)
          return unless scopes.include?("preferences")

          keys = data.to_h.slice(:default_landing_page, :preferred_month_view, :financial_rhythm).keys
          { preferences: keys.size, keys: keys }
        end

        def failure(message)
          { success: false, error: message }
        end
      end
    end
  end
end
