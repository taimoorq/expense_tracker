require "set"

module Platform
  module Backup
    module V2
      class StagingValidator
        MAX_RECORDS = 250_000
        MAX_PAYLOAD_BYTES = 100.megabytes

        COLLECTION_PATHS = {
          account: %i[accounts records],
          category: %i[reference_data categories],
          period: %i[budget_months periods],
          template: %i[planning_templates records],
          item: %i[budget_months items],
          occurrence: %i[budget_months recurring_occurrences],
          month_close: %i[budget_months month_closes],
          month_close_item_snapshot: %i[budget_months month_close_item_snapshots],
          month_close_transaction_snapshot: %i[budget_months month_close_transaction_snapshots],
          import_profile: %i[account_activity import_profiles],
          import_batch: %i[account_activity import_batches],
          import_row: %i[account_activity import_rows],
          transaction: %i[account_activity transactions],
          posting: %i[account_activity account_postings],
          allocation: %i[account_activity budget_allocations],
          observation: %i[accounts balance_observations]
        }.freeze

        REFERENCES = {
          template: {
            category_external_id: [ :category, false ],
            source_account_external_id: [ :account, false ],
            destination_account_external_id: [ :account, false ]
          },
          item: {
            budget_period_external_id: [ :period, true ],
            category_external_id: [ :category, false ],
            recurring_occurrence_external_id: [ :occurrence, false ],
            intended_source_account_external_id: [ :account, false ],
            intended_destination_account_external_id: [ :account, false ]
          },
          occurrence: {
            planning_template_external_id: [ :template, true ],
            budget_period_external_id: [ :period, true ],
            budget_item_external_id: [ :item, false ]
          },
          month_close: {
            budget_period_external_id: [ :period, true ],
            reopens_month_close_external_id: [ :month_close, false ]
          },
          month_close_item_snapshot: {
            month_close_external_id: [ :month_close, true ],
            budget_item_external_id: [ :item, true ]
          },
          month_close_transaction_snapshot: {
            month_close_external_id: [ :month_close, true ],
            financial_transaction_external_id: [ :transaction, true ]
          },
          import_profile: { account_external_id: [ :account, false ] },
          import_batch: {
            account_external_id: [ :account, false ],
            import_profile_external_id: [ :import_profile, false ]
          },
          import_row: {
            import_batch_external_id: [ :import_batch, true ],
            financial_transaction_external_id: [ :transaction, false ]
          },
          transaction: {
            category_external_id: [ :category, false ],
            import_row_external_id: [ :import_row, false ],
            reversal_transaction_external_id: [ :transaction, false ]
          },
          posting: {
            financial_transaction_external_id: [ :transaction, true ],
            account_external_id: [ :account, true ]
          },
          allocation: {
            budget_item_external_id: [ :item, true ],
            financial_transaction_external_id: [ :transaction, true ]
          },
          observation: {
            account_external_id: [ :account, true ],
            source_import_batch_external_id: [ :import_batch, false ],
            source_import_row_external_id: [ :import_row, false ]
          }
        }.freeze

        def initialize(payload:, scopes:)
          @payload = payload.to_h.deep_symbolize_keys
          @scopes = Array(scopes).map(&:to_s)
          @records = {}
          @ids = {}
        end

        def call
          preview = Preview.new(payload: payload, scopes: scopes).call
          return preview unless preview[:success]
          return preview.merge(manifest: { "preferences" => 1 }) unless financial_restore?
          return failure("The backup is too large to stage safely.") if payload_size > MAX_PAYLOAD_BYTES

          collect_records!
          return failure("The backup exceeds the #{MAX_RECORDS} record staging limit.") if record_count > MAX_RECORDS

          validate_references!
          preview.merge(manifest: records.transform_values(&:size).stringify_keys)
        rescue KeyError
          failure("The backup is missing a required financial collection.")
        rescue RelationshipError => error
          failure(error.message)
        end

        private

        attr_reader :ids, :payload, :records, :scopes

        def financial_restore?
          (scopes & Preview::FINANCIAL_SCOPES).any?
        end

        def payload_size
          Platform::CanonicalJson.dump(payload).bytesize
        end

        def record_count
          records.values.sum(&:size)
        end

        def collect_records!
          data = payload.fetch(:data)
          COLLECTION_PATHS.each do |type, path|
            collection = path.reduce(data) { |value, key| value.fetch(key) }
            records[type] = Array(collection).map(&:to_h).map(&:deep_symbolize_keys)
            ids[type] = Set.new
            records[type].each { |record| register!(type, record) }
          end
          collect_nested_template_records!
        end

        def collect_nested_template_records!
          records[:recurrence_rule] = records.fetch(:template).filter_map { |record| record[:recurrence_rule]&.to_h&.deep_symbolize_keys }
          ids[:recurrence_rule] = Set.new
          records[:recurrence_rule].each { |record| register!(:recurrence_rule, record) }

          records.fetch(:template).each do |record|
            policy = record[:credit_card_payment_policy]&.to_h&.deep_symbolize_keys
            next unless policy

            validate_reference!(:credit_card_payment_policy, policy, :liability_account_external_id, :account, true)
            validate_reference!(:credit_card_payment_policy, policy, :payment_account_external_id, :account, true)
          end
        end

        def register!(type, record)
          external_id = record.fetch(:external_id).to_s
          unless external_id.match?(Importer::UUID_PATTERN)
            raise RelationshipError, "The backup contains an invalid #{type.to_s.humanize.downcase} external ID."
          end
          unless ids.fetch(type).add?(external_id)
            raise RelationshipError, "The backup repeats a #{type.to_s.humanize.downcase} external ID."
          end
        end

        def validate_references!
          REFERENCES.each do |type, fields|
            records.fetch(type).each do |record|
              fields.each do |field, (target_type, required)|
                validate_reference!(type, record, field, target_type, required)
              end
            end
          end
        end

        def validate_reference!(source_type, record, field, target_type, required)
          value = record[field].presence
          if value.blank?
            raise RelationshipError, "The backup has a #{source_type.to_s.humanize.downcase} without its required #{target_type.to_s.humanize.downcase}." if required
            return
          end
          unless value.to_s.match?(Importer::UUID_PATTERN) && ids.fetch(target_type).include?(value.to_s)
            raise RelationshipError, "The backup references a missing #{target_type.to_s.humanize.downcase}."
          end
        end

        def failure(message)
          { success: false, error: message }
        end

        class RelationshipError < StandardError; end
      end
    end
  end
end
