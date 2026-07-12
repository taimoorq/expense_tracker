module Accounts
  module ActivityImports
    class Importer
      def initialize(user:, account:, preview:)
        @user = user
        @account = account
        @preview = preview.deep_symbolize_keys
      end

      def call
        return failed_from_preview unless preview[:ok]

        counts = { imported_count: 0, duplicate_count: 0 }
        import_record = nil

        ApplicationRecord.transaction do
          import_record = create_import_record
          counts = create_activity_rows(import_record)
          import_record.update!(
            imported_count: counts[:imported_count],
            duplicate_count: counts[:duplicate_count]
          )
        end

        {
          ok: true,
          import: import_record,
          imported_count: counts[:imported_count],
          duplicate_count: counts[:duplicate_count],
          warnings: Array(preview[:warnings]),
          errors: []
        }
      rescue ActiveRecord::RecordInvalid => error
        { ok: false, error: error.record.errors.full_messages.to_sentence.presence || error.message, warnings: Array(preview[:warnings]), errors: [] }
      end

      private

      attr_reader :account, :preview, :user

      def create_import_record
        account.account_activity_imports.create!(
          user: user,
          original_filename: preview[:original_filename],
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

      def import_metadata
        metadata = (preview[:metadata] || {}).to_h.stringify_keys
        metadata["headers"] = Array(preview[:headers])
        metadata["institution_balance"] = preview[:institution_balance] if preview[:institution_balance].present?
        metadata["institution_balance_as_of"] = preview[:institution_balance_as_of] if preview[:institution_balance_as_of].present?
        metadata["institution_name"] = preview[:institution_name] if preview[:institution_name].present?
        metadata.compact
      end

      def create_activity_rows(import_record)
        imported_count = 0
        duplicate_count = 0

        Array(preview[:rows]).each do |row|
          attributes = row.deep_symbolize_keys

          if duplicate_row?(attributes)
            duplicate_count += 1
            next
          end

          import_record.account_activities.create!(
            user: user,
            account: account,
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
            raw_payload: attributes[:raw_payload]
          )
          imported_count += 1
        rescue ActiveRecord::RecordNotUnique
          duplicate_count += 1
        end

        { imported_count: imported_count, duplicate_count: duplicate_count }
      end

      def duplicate_row?(attributes)
        account.account_activities.exists?(fingerprint: attributes[:fingerprint])
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
