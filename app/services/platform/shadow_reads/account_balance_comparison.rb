module Platform
  module ShadowReads
    class AccountBalanceComparison
      COMPARED_FIELDS = %i[
        balance_available
        base_balance
        paid_delta
        planned_delta
        current_balance
        projected_balance
        paid_entries_count
        planned_entries_count
      ].freeze

      Result = Data.define(:account, :as_of, :legacy, :target, :mismatched_fields) do
        def matched?
          mismatched_fields.empty?
        end

        def as_json(*)
          {
            account_id: account.id,
            as_of: as_of,
            matched: matched?,
            mismatched_fields: mismatched_fields
          }
        end
      end

      def self.call(account:, as_of: Date.current, persist: true)
        new(account: account, as_of: as_of, persist: persist).call
      end

      def initialize(account:, as_of:, persist:)
        @account = account
        @as_of = as_of.to_date
        @persist = persist
      end

      def call
        legacy = Accounts::BalanceResolver.new(account: account, as_of: as_of).call
        target = Accounts::TargetBalanceResolver.new(account: account, as_of: as_of).call
        mismatched_fields = COMPARED_FIELDS.reject { |field| legacy.public_send(field) == target.public_send(field) }
        result = Result.new(
          account: account,
          as_of: as_of,
          legacy: legacy,
          target: target,
          mismatched_fields: mismatched_fields
        )
        persist_result(result) if persist
        result
      end

      private

      attr_reader :account, :as_of, :persist

      def persist_result(result)
        workspace = account.budget_workspace
        return if workspace.blank?

        discrepancy = workspace.migration_discrepancies.find_or_initialize_by(
          legacy_record_type: "Account",
          legacy_record_id: account.id,
          code: "shadow_account_balance_mismatch"
        )
        if result.matched?
          return if discrepancy.new_record?

          discrepancy.update!(
            status: "resolved",
            resolved_at: Time.current,
            redacted_details: { "last_compared_on" => as_of }
          )
        else
          discrepancy.update!(
            status: "open",
            resolved_at: nil,
            redacted_details: {
              "as_of" => as_of,
              "mismatched_fields" => result.mismatched_fields.map(&:to_s)
            }
          )
        end
      end
    end
  end
end
