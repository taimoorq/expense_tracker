module Platform
  module Backup
    module V2
      class Importer
        SCOPES = Platform::UserDataExport::SCOPES
        FINANCIAL_SCOPES = Preview::FINANCIAL_SCOPES
        UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

        ACCOUNT_FIELDS = %i[name institution_name kind active include_in_net_worth include_in_cash notes currency_code archived_at created_at updated_at].freeze
        CATEGORY_FIELDS = %i[name flow_kind budget_group color_token display_order archived_at created_at updated_at].freeze
        OBSERVATION_FIELDS = %i[observed_at effective_through_at balance available_balance currency_code source_kind status notes created_at updated_at].freeze
        PERIOD_FIELDS = %i[starts_on currency_code state notes created_at updated_at].freeze
        TEMPLATE_FIELDS = %i[name kind flow_kind budget_group default_amount currency_code active_from active_until notes archived_at created_at updated_at].freeze
        RULE_FIELDS = %i[cadence interval_count anchor_on day_one day_two starts_on ends_on weekend_policy created_at updated_at].freeze
        TERM_FIELDS = %i[total_due opening_paid_adjustment monthly_target target_completion_on created_at updated_at].freeze
        POLICY_FIELDS = %i[due_day minimum_payment priority estimate_policy created_at updated_at].freeze
        ITEM_FIELDS = %i[flow_kind budget_group planned_amount currency_code scheduled_on state origin_kind name_snapshot payee_snapshot category_snapshot priority_classification notes voided_at void_reason created_at updated_at].freeze
        OCCURRENCE_FIELDS = %i[scheduled_on slot_key state created_at updated_at].freeze
        CLOSE_FIELDS = %i[state calculation_version planned_income planned_outflow planned_net actual_income actual_outflow actual_net remaining_income remaining_outflow forecast_income forecast_outflow forecast_net income_variance outflow_variance unresolved_count unmatched_count calculation_input_digest closed_at created_at updated_at].freeze
        CLOSE_ITEM_FIELDS = %i[flow_kind budget_group name_snapshot category_snapshot scheduled_on planned_amount actual_amount remaining_amount currency_code created_at updated_at].freeze
        CLOSE_TRANSACTION_FIELDS = %i[flow_kind origin_kind description_snapshot category_snapshot effective_on gross_amount allocated_amount currency_code created_at updated_at].freeze
        PROFILE_FIELDS = %i[name parser_name parser_version header_row_number column_mapping amount_strategy fingerprint_version active created_at updated_at].freeze
        BATCH_FIELDS = %i[import_kind original_filename file_digest idempotency_key parser_version mapping_version fingerprint_version coverage_starts_on coverage_ends_on status row_count imported_count duplicate_count error_count redacted_metadata warnings committed_at failed_at failure_code reverted_at created_at updated_at].freeze
        ROW_FIELDS = %i[row_number provider_transaction_id fingerprint fingerprint_version raw_payload normalized_payload normalization_result status error_code error_message created_at updated_at].freeze
        TRANSACTION_FIELDS = %i[effective_on posted_on description payee memo gross_amount currency_code flow_kind state origin_kind provider_transaction_id idempotency_key voided_at void_reason created_at updated_at].freeze
        POSTING_FIELDS = %i[amount currency_code role sequence_number created_at updated_at].freeze
        ALLOCATION_FIELDS = %i[amount currency_code match_kind match_confidence matched_at created_at updated_at].freeze

        def initialize(user:, payload:, scopes:, replace_existing: false, checkpoint: nil, operation_run: nil, transfer: nil)
          @user = user
          @payload = payload.to_h.deep_symbolize_keys
          @scopes = Array(scopes).map(&:to_s) & SCOPES
          @maps = Hash.new { |hash, type| hash[type] = {} }
          @counts = Hash.new(0)
          @replace_existing = replace_existing
          @checkpoint = checkpoint
          @managed_operation = operation_run
          @supplied_transfer = transfer
        end

        def call
          validation = Preview.new(payload: payload, scopes: scopes).call
          return validation.slice(:success, :error) unless validation[:success]

          bootstrap_workspace!
          prior = prior_success
          return { success: true, counts: prior.result_counts } if prior.present?

          @transfer = prepare_transfer!
          outcome = execute_restore
          result = { success: true, counts: outcome.value.result_counts, transfer: outcome.value }
          report_success(outcome)
          result
        rescue ActiveRecord::RecordInvalid => error
          record_failure(error)
          report_failure(error)
          failure(error.record.errors.full_messages.to_sentence.presence || "The backup contains an invalid record.")
        rescue RelationshipError, Platform::Backup::V2::LegacyProjection::ProjectionError, ArgumentError, KeyError => error
          record_failure(error)
          report_failure(error)
          failure(error.message)
        rescue StandardError => error
          record_failure(error)
          report_failure(error)
          Rails.error.report(error, handled: true, context: { operation: "backup_v2_restore" })
          failure("Backup V2 restore failed safely (#{error.class.name}).")
        end

        private

        attr_reader :checkpoint, :counts, :managed_operation, :maps, :membership, :payload,
          :replace_existing, :scopes, :supplied_transfer, :transfer, :user, :workspace

        def bootstrap_workspace!
          metadata = payload.fetch(:workspace)
          currency = metadata.fetch(:default_currency_code).to_s
          raise ArgumentError, "The backup workspace currency is invalid." unless currency.match?(/\A[A-Z]{3}\z/)

          @workspace = BudgetWorkspace.find_or_initialize_by(legacy_owner_user: user)
          if workspace.persisted? && workspace.default_currency_code != currency
            raise ArgumentError, "The backup currency does not match this workspace."
          end
          workspace.assign_attributes(
            name: metadata[:name].presence || "Restored budget",
            default_currency_code: currency,
            status: "active",
            closed_at: nil
          )
          workspace.save!
          @membership = workspace.workspace_memberships.find_or_create_by!(user: user) do |record|
            record.role = "owner"
            record.status = "active"
            record.joined_at = Time.current
          end
        end

        def execute_restore
          if managed_operation
            completion = execute_restore_command(managed_operation)
            return Platform::Operations::Executor::Outcome.new(
              operation_run: managed_operation,
              value: completion.value,
              replayed: false
            )
          end

          Platform::Operations::Executor.call(
            workspace: workspace,
            actor_membership: membership,
            operation_type: "backup_v2_restore",
            idempotency_key: "backup-v2:#{payload.fetch(:payload_checksum)}:#{checkpoint&.id || 'empty'}",
            request: { payload_checksum: payload.fetch(:payload_checksum), scopes: scopes, checkpoint_id: checkpoint&.id },
            redacted_parameters: { "format_version" => 2, "scopes" => scopes },
            retryable: true,
            on_replay: ->(reference) { DataTransferRun.find(reference.fetch("id")) }
          ) { |operation| execute_restore_command(operation) }
        end

        def execute_restore_command(operation)
          transfer.update!(operation_run: operation)
          prepare_destination! if financial_restore?
          import_financial_bundle if financial_restore?
          project_legacy_compatibility!(operation) if financial_restore?
          import_preferences if scopes.include?("preferences")
          mark_workspace_restore_ready! if financial_restore?
          finish_transfer!(operation)
          Platform::Operations::Executor::Completion.new(
            value: transfer,
            result_counts: counts,
            result_reference: { "type" => "DataTransferRun", "id" => transfer.id }
          )
        end

        def import_financial_bundle
          data = payload.fetch(:data)
          import_accounts(data.fetch(:accounts))
          import_categories(data.fetch(:reference_data).fetch(:categories))
          import_periods(data.fetch(:budget_months).fetch(:periods))
          import_templates(data.fetch(:planning_templates).fetch(:records))
          import_items(data.fetch(:budget_months).fetch(:items))
          import_occurrences(data.fetch(:budget_months).fetch(:recurring_occurrences))
          link_item_occurrences(data.fetch(:budget_months).fetch(:items))
          import_month_closes(data.fetch(:budget_months).fetch(:month_closes))
          import_profiles(data.fetch(:account_activity).fetch(:import_profiles))
          import_batches(data.fetch(:account_activity).fetch(:import_batches))
          import_rows(data.fetch(:account_activity).fetch(:import_rows))
          import_transactions(data.fetch(:account_activity).fetch(:transactions))
          link_transaction_relationships(data.fetch(:account_activity))
          import_postings(data.fetch(:account_activity).fetch(:account_postings))
          import_allocations(data.fetch(:account_activity).fetch(:budget_allocations))
          import_month_close_snapshots(data.fetch(:budget_months))
          import_observations(data.fetch(:accounts).fetch(:balance_observations))
        end

        def import_accounts(data)
          Array(data.fetch(:records)).each do |record|
            account = user.accounts.create!(attributes(record, ACCOUNT_FIELDS).merge(budget_workspace: workspace))
            register!(:account, record, account)
            counts["accounts"] += 1
          end
        end

        def import_categories(records)
          Array(records).each do |record|
            category = workspace.categories.create!(attributes(record, CATEGORY_FIELDS))
            register!(:category, record, category)
            counts["categories"] += 1
          end
        end

        def import_periods(records)
          Array(records).each do |record|
            period = workspace.budget_periods.create!(attributes(record, PERIOD_FIELDS))
            register!(:period, record, period)
            counts["budget_periods"] += 1
          end
        end

        def import_templates(records)
          Array(records).each do |record|
            template = workspace.planning_templates.create!(
              attributes(record, TEMPLATE_FIELDS).merge(
                category: lookup(:category, record[:category_external_id]),
                source_account: lookup(:account, record[:source_account_external_id]),
                destination_account: lookup(:account, record[:destination_account_external_id])
              )
            )
            register!(:template, record, template)
            import_template_details(record, template)
            counts["planning_templates"] += 1
          end
        end

        def import_template_details(record, template)
          if record[:recurrence_rule].present?
            rule_data = record.fetch(:recurrence_rule)
            rule = template.create_recurrence_rule!(attributes(rule_data, RULE_FIELDS))
            register!(:recurrence_rule, rule_data, rule)
            Array(rule_data[:months]).each { |month_number| rule.recurrence_months.create!(month_number: month_number) }
          end
          if record[:payment_plan_term].present?
            template.create_payment_plan_term!(attributes(record.fetch(:payment_plan_term), TERM_FIELDS))
          end
          if record[:credit_card_payment_policy].present?
            policy = record.fetch(:credit_card_payment_policy)
            template.create_credit_card_payment_policy!(
              attributes(policy, POLICY_FIELDS).merge(
                budget_workspace: workspace,
                liability_account: lookup!(:account, policy[:liability_account_external_id]),
                payment_account: lookup!(:account, policy[:payment_account_external_id])
              )
            )
          end
        end

        def import_items(records)
          Array(records).each do |record|
            item = workspace.budget_items.create!(
              attributes(record, ITEM_FIELDS).merge(
                budget_period: lookup!(:period, record[:budget_period_external_id]),
                category: lookup(:category, record[:category_external_id]),
                intended_source_account: lookup(:account, record[:intended_source_account_external_id]),
                intended_destination_account: lookup(:account, record[:intended_destination_account_external_id])
              )
            )
            register!(:item, record, item)
            counts["budget_items"] += 1
          end
        end

        def import_occurrences(records)
          Array(records).each do |record|
            occurrence = workspace.recurring_occurrences.create!(
              attributes(record, OCCURRENCE_FIELDS).merge(
                planning_template: lookup!(:template, record[:planning_template_external_id]),
                budget_period: lookup!(:period, record[:budget_period_external_id]),
                budget_item: lookup(:item, record[:budget_item_external_id])
              )
            )
            register!(:occurrence, record, occurrence)
            counts["recurring_occurrences"] += 1
          end
        end

        def link_item_occurrences(records)
          Array(records).each do |record|
            occurrence = lookup(:occurrence, record[:recurring_occurrence_external_id])
            lookup!(:item, external_id(record)).update!(recurring_occurrence: occurrence) if occurrence.present?
          end
        end

        def import_month_closes(records)
          Array(records).each do |record|
            close = workspace.month_closes.create!(
              attributes(record, CLOSE_FIELDS).merge(
                budget_period: lookup!(:period, record[:budget_period_external_id]),
                closed_by_membership: membership
              )
            )
            register!(:month_close, record, close)
            counts["month_closes"] += 1
          end
          Array(records).each do |record|
            reopened = lookup(:month_close, record[:reopens_month_close_external_id])
            lookup!(:month_close, external_id(record)).update_column(:reopens_month_close_id, reopened.id) if reopened.present?
          end
        end

        def import_month_close_snapshots(data)
          Array(data.fetch(:month_close_item_snapshots, [])).each do |record|
            workspace.month_close_item_snapshots.create!(
              attributes(record, CLOSE_ITEM_FIELDS).merge(
                month_close: lookup!(:month_close, record[:month_close_external_id]),
                budget_item: lookup!(:item, record[:budget_item_external_id])
              )
            )
            counts["month_close_item_snapshots"] += 1
          end
          Array(data.fetch(:month_close_transaction_snapshots, [])).each do |record|
            workspace.month_close_transaction_snapshots.create!(
              attributes(record, CLOSE_TRANSACTION_FIELDS).merge(
                month_close: lookup!(:month_close, record[:month_close_external_id]),
                financial_transaction: lookup!(:transaction, record[:financial_transaction_external_id])
              )
            )
            counts["month_close_transaction_snapshots"] += 1
          end
        end

        def import_profiles(records)
          Array(records).each do |record|
            profile = workspace.import_profiles.create!(
              attributes(record, PROFILE_FIELDS).merge(account: lookup(:account, record[:account_external_id]))
            )
            register!(:import_profile, record, profile)
            counts["import_profiles"] += 1
          end
        end

        def import_batches(records)
          Array(records).each do |record|
            batch = workspace.import_batches.create!(
              attributes(record, BATCH_FIELDS).merge(
                account: lookup(:account, record[:account_external_id]),
                import_profile: lookup(:import_profile, record[:import_profile_external_id]),
                actor_membership: membership
              )
            )
            register!(:import_batch, record, batch)
            counts["import_batches"] += 1
          end
        end

        def import_rows(records)
          Array(records).each do |record|
            row = workspace.import_rows.create!(
              attributes(record, ROW_FIELDS).merge(
                import_batch: lookup!(:import_batch, record[:import_batch_external_id])
              )
            )
            register!(:import_row, record, row)
            counts["import_rows"] += 1
          end
        end

        def import_transactions(records)
          Array(records).each do |record|
            transaction = workspace.financial_transactions.create!(
              attributes(record, TRANSACTION_FIELDS).merge(
                category: lookup(:category, record[:category_external_id])
              )
            )
            register!(:transaction, record, transaction)
            counts["financial_transactions"] += 1
          end
        end

        def link_transaction_relationships(data)
          Array(data.fetch(:transactions)).each do |record|
            transaction = lookup!(:transaction, external_id(record))
            transaction.update_columns(
              import_row_id: lookup(:import_row, record[:import_row_external_id])&.id,
              reversal_transaction_id: lookup(:transaction, record[:reversal_transaction_external_id])&.id
            )
          end
          Array(data.fetch(:import_rows)).each do |record|
            transaction = lookup(:transaction, record[:financial_transaction_external_id])
            lookup!(:import_row, external_id(record)).update_column(:financial_transaction_id, transaction.id) if transaction.present?
          end
        end

        def import_postings(records)
          Array(records).each do |record|
            workspace.account_postings.create!(
              attributes(record, POSTING_FIELDS).merge(
                financial_transaction: lookup!(:transaction, record[:financial_transaction_external_id]),
                account: lookup!(:account, record[:account_external_id])
              )
            )
            counts["account_postings"] += 1
          end
        end

        def import_allocations(records)
          Array(records).each do |record|
            workspace.budget_allocations.create!(
              attributes(record, ALLOCATION_FIELDS).merge(
                budget_item: lookup!(:item, record[:budget_item_external_id]),
                financial_transaction: lookup!(:transaction, record[:financial_transaction_external_id]),
                matched_by_membership: membership
              )
            )
            counts["budget_allocations"] += 1
          end
        end

        def import_observations(records)
          Array(records).each do |record|
            workspace.balance_observations.create!(
              attributes(record, OBSERVATION_FIELDS).merge(
                account: lookup!(:account, record[:account_external_id]),
                actor_membership: membership,
                source_import_batch: lookup(:import_batch, record[:source_import_batch_external_id]),
                source_import_row: lookup(:import_row, record[:source_import_row_external_id])
              )
            )
            counts["balance_observations"] += 1
          end
        end

        def import_preferences
          values = payload.fetch(:data).fetch(:preferences).slice(
            :default_landing_page,
            :preferred_month_view,
            :financial_rhythm
          ).compact
          user.update!(values)
          counts["preferences"] = values.size
        end

        def attributes(record, allowed)
          record.fetch(:attributes).to_h.symbolize_keys.slice(*allowed)
        end

        def register!(type, record, target)
          source_id = external_id(record)
          raise RelationshipError, "The backup repeats a #{type.to_s.humanize.downcase} external ID." if maps[type].key?(source_id)

          maps[type][source_id] = target
        end

        def lookup(type, source_id)
          return if source_id.blank?

          validate_external_id!(source_id)
          maps[type][source_id.to_s]
        end

        def lookup!(type, source_id)
          lookup(type, source_id) || raise(
            RelationshipError,
            "The backup references a missing #{type.to_s.humanize.downcase}."
          )
        end

        def external_id(record)
          value = record.fetch(:external_id).to_s
          validate_external_id!(value)
          value
        end

        def validate_external_id!(value)
          return if value.to_s.match?(UUID_PATTERN)

          raise RelationshipError, "The backup contains an invalid external ID."
        end

        def financial_restore?
          (scopes & FINANCIAL_SCOPES).any?
        end

        def ensure_empty_target!
          models = [
            workspace.accounts,
            workspace.categories,
            workspace.budget_periods,
            workspace.planning_templates,
            workspace.financial_transactions,
            workspace.import_batches,
            workspace.balance_observations
          ]
          return unless models.any?(&:exists?) || user.accounts.exists? || user.budget_months.exists? || user.expense_entries.exists?

          raise RelationshipError,
            "Backup V2 restore requires an empty destination. Existing data was not changed."
        end

        def prepare_destination!
          if replace_existing
            unless checkpoint&.budget_workspace_id == workspace.id && checkpoint.available?
              raise RelationshipError, "A current recovery checkpoint is required before replacing this budget."
            end
            Platform::Backup::ReplacementCleaner.call(user: user, workspace: workspace)
          else
            ensure_empty_target!
          end
        end

        def mark_workspace_restore_ready!
          workspace.update!(
            target_backfill_version: Platform::TargetBackfill::WorkspaceBootstrap::VERSION,
            target_backfilled_at: Time.current,
            target_reads_enabled: true,
            target_writes_enabled: true
          )
        end

        def project_legacy_compatibility!(operation)
          projected_counts = Platform::Backup::V2::LegacyProjection.new(
            user: user,
            workspace: workspace,
            operation_run: operation
          ).call
          counts.merge!(projected_counts)
        end

        def prepare_transfer!
          if supplied_transfer
            unless supplied_transfer.budget_workspace_id == workspace.id && supplied_transfer.payload_checksum == payload.fetch(:payload_checksum)
              raise RelationshipError, "The staged transfer does not match this backup."
            end
            supplied_transfer.update!(
              actor_membership: membership,
              checkpoint_reference: checkpoint&.id&.to_s || "empty-target",
              state: "running",
              started_at: Time.current,
              completed_at: nil,
              error_code: nil
            )
            return supplied_transfer
          end

          workspace.data_transfer_runs.create!(
            actor_membership: membership,
            operation: "restore",
            payload_format_version: "2",
            envelope_version: Platform::UserDataBackupCodec::ENCRYPTED_FORMAT_VERSION.to_s,
            payload_checksum: payload.fetch(:payload_checksum),
            selected_scopes: scopes,
            checkpoint_reference: checkpoint&.id&.to_s || "empty-target",
            state: "running",
            result_counts: {},
            started_at: Time.current
          )
        end

        def finish_transfer!(operation)
          transfer.update!(
            operation_run: operation,
            state: "succeeded",
            result_counts: counts,
            completed_at: Time.current
          )
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: operation,
            entity: transfer,
            action: "backup_restore",
            changed_fields: %i[state selected_scopes payload_format_version]
          )
        end

        def prior_success
          scope = workspace.data_transfer_runs
            .operation_restore
            .state_succeeded
            .where(payload_checksum: payload.fetch(:payload_checksum), selected_scopes: scopes)
          scope = scope.where(checkpoint_reference: checkpoint.id.to_s) if checkpoint.present?
          scope.find_by(checkpoint_reference: checkpoint.present? ? checkpoint.id.to_s : "empty-target")
        end

        def record_failure(error)
          return if transfer.blank? || !transfer.persisted? || transfer.state_failed?

          transfer.reload
          transfer.update!(
            state: "failed",
            error_code: error.class.name.underscore.tr("/", "_"),
            completed_at: Time.current
          )
        rescue ActiveRecord::RecordInvalid
          nil
        end

        def failure(message)
          { success: false, error: message }
        end

        def report_success(outcome)
          Platform::OperationalEvents.notify(
            "backup_restore.succeeded",
            workspace_id: workspace.id,
            transfer_id: transfer.id,
            operation_id: outcome.operation_run.id,
            result_count: transfer.result_counts.values.grep(Numeric).sum,
            replacement: replace_existing
          )
        end

        def report_failure(error)
          Platform::OperationalEvents.notify(
            "backup_restore.failed",
            workspace_id: workspace&.id,
            transfer_id: transfer&.id,
            error_class: error.class.name,
            replacement: replace_existing
          )
        end

        class RelationshipError < StandardError; end
      end
    end
  end
end
