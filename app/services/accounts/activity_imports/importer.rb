require "digest"

module Accounts
  module ActivityImports
    class Importer
      INSERT_BATCH_SIZE = 1_000

      def initialize(user:, account:, preview:)
        @user = user
        @account = account
        @preview = preview.deep_symbolize_keys
      end

      def call
        return failed_from_preview unless preview[:ok]

        counts = { imported_count: 0, duplicate_count: 0 }
        import_record = nil
        replayed = false

        ApplicationRecord.transaction do
          import_record = find_or_create_import_record
          replayed = !import_record.previously_new_record?

          if replayed
            counts = import_record.slice(:imported_count, :duplicate_count).symbolize_keys
          else
            counts = create_activity_rows(import_record)
            import_record.update!(
              imported_count: counts[:imported_count],
              duplicate_count: counts[:duplicate_count]
            )
          end
          Platform::TargetSync::AccountActivityImportWriter.call(legacy_import: import_record)
        end

        {
          ok: true,
          import: import_record,
          imported_count: counts[:imported_count],
          duplicate_count: counts[:duplicate_count],
          replayed: replayed,
          warnings: Array(preview[:warnings]),
          errors: []
        }
      rescue ActiveRecord::RecordInvalid => error
        { ok: false, error: error.record.errors.full_messages.to_sentence.presence || error.message, warnings: Array(preview[:warnings]), errors: [] }
      rescue Platform::TargetSync::WriteRejected => error
        { ok: false, error: error.message, warnings: Array(preview[:warnings]), errors: [] }
      end

      private

      attr_reader :account, :preview, :user

      def find_or_create_import_record
        user.account_activity_imports.create_or_find_by!(
          commit_idempotency_key: commit_idempotency_key
        ) do |import_record|
          import_record.assign_attributes(
            account: account,
            original_filename: preview[:original_filename],
            file_digest: preview[:file_digest],
            header_row_number: preview[:header_row_number],
            column_mapping: preview[:column_mapping],
            amount_strategy: preview[:amount_strategy],
            rows_count: Array(preview[:rows]).size,
            imported_count: 0,
            duplicate_count: 0,
            warning_messages: Array(preview[:warnings]),
            started_on: parse_date(preview[:started_on]),
            ended_on: parse_date(preview[:ended_on]),
            metadata: import_metadata
          )
        end
      end

      def import_metadata
        metadata = (preview[:metadata] || {}).to_h.stringify_keys
        metadata["headers"] = Array(preview[:headers])
        metadata["institution_balance"] = preview[:institution_balance] if preview[:institution_balance].present?
        metadata["institution_balance_as_of"] = preview[:institution_balance_as_of] if preview[:institution_balance_as_of].present?
        metadata["institution_name"] = preview[:institution_name] if preview[:institution_name].present?
        metadata.compact
      end

      def create_activity_rows(import_record)
        timestamp = Time.current
        rows = Array(preview[:rows]).map do |row|
          activity_attributes(import_record, row.deep_symbolize_keys, timestamp: timestamp)
        end
        imported_count = rows.each_slice(INSERT_BATCH_SIZE).sum do |batch|
          AccountActivity.insert_all(
            batch,
            unique_by: "index_account_activities_on_account_id_and_fingerprint",
            returning: [ :id ]
          ).rows.size
        end

        {
          imported_count: imported_count,
          duplicate_count: rows.size - imported_count
        }
      end

      def activity_attributes(import_record, attributes, timestamp:)
        {
          user_id: user.id,
          budget_workspace_id: import_record.budget_workspace_id,
          account_id: account.id,
          account_activity_import_id: import_record.id,
          transaction_on: parse_date(attributes[:transaction_on]),
          posted_on: parse_date(attributes[:posted_on]),
          description: attributes[:description],
          category: attributes[:category],
          activity_type: attributes[:activity_type],
          memo: attributes[:memo],
          raw_amount: attributes[:raw_amount],
          amount: attributes[:amount],
          account_delta: attributes[:account_delta],
          row_number: attributes[:row_number],
          fingerprint: attributes[:fingerprint],
          raw_payload: attributes[:raw_payload],
          created_at: timestamp,
          updated_at: timestamp
        }
      end

      def commit_idempotency_key
        @commit_idempotency_key ||= preview[:commit_idempotency_key].presence ||
          Digest::SHA256.hexdigest(
            [
              user.id,
              account.id,
              preview[:file_digest],
              preview[:original_filename],
              preview[:column_mapping],
              preview[:amount_strategy],
              Array(preview[:rows]).map { |row| row.to_h[:fingerprint] || row.to_h["fingerprint"] }
            ].to_json
          )
      end

      def parse_date(value)
        return if value.blank?
        return value if value.is_a?(Date)

        Date.parse(value.to_s)
      end

      def failed_from_preview
        message = Array(preview[:errors]).presence&.to_sentence || "Account activity import failed."
        { ok: false, error: message, warnings: Array(preview[:warnings]), errors: Array(preview[:errors]) }
      end
    end
  end
end
