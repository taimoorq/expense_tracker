require "digest"

module Platform
  module Backup
    module V2
      class Exporter
        FORMAT_NAME = Platform::UserDataExport::FORMAT_NAME
        FORMAT_VERSION = 2
        CALCULATION_VERSION = Budgeting::PeriodSummary::CALCULATION_VERSION
        SCOPES = Platform::UserDataExport::SCOPES

        attr_reader :scopes

        def initialize(user:, scopes:)
          @user = user
          @workspace = BudgetWorkspace.find_by!(legacy_owner_user_id: user.id)
          @membership = workspace.workspace_memberships.status_active.find_by!(user: user)
          @scopes = Array(scopes).map(&:to_s) & SCOPES
        end

        def filename(password: nil)
          suffix = password.present? ? "-encrypted" : nil
          "finance-tracking-backup-v2-#{Time.current.strftime('%Y%m%d-%H%M%S')}#{suffix}.json"
        end

        def as_json
          @as_json ||= ApplicationRecord.transaction(isolation: :repeatable_read) do
            payload = {
              format: FORMAT_NAME,
              version: FORMAT_VERSION,
              exported_at: Time.current.iso8601,
              scopes: scopes,
              workspace: {
                external_id: workspace.id,
                name: workspace.name,
                default_currency_code: workspace.default_currency_code,
                calculation_version: CALCULATION_VERSION
              },
              data: export_data
            }
            payload.merge(payload_checksum: checksum(payload))
          end
        end

        def to_json(*_args)
          JSON.pretty_generate(as_json)
        end

        def backup_json(password: nil)
          payload = as_json
          record_export!(payload)
          Platform::UserDataBackupCodec.encode(payload: payload, password: password)
        end

        private

        attr_reader :membership, :user, :workspace

        def export_data
          {}.tap do |data|
            if (scopes & %w[planning_templates budget_months account_activity]).any?
              data[:reference_data] = { categories: serialize_categories }
            end
            data[:accounts] = serialize_accounts if scopes.include?("accounts")
            data[:planning_templates] = serialize_planning_templates if scopes.include?("planning_templates")
            data[:budget_months] = serialize_budget_months if scopes.include?("budget_months")
            data[:account_activity] = serialize_account_activity if scopes.include?("account_activity")
            data[:preferences] = serialize_preferences if scopes.include?("preferences")
          end
        end

        def serialize_preferences
          {
            default_landing_page: user.default_landing_page,
            preferred_month_view: user.preferred_month_view,
            financial_rhythm: user.financial_rhythm
          }
        end

        def serialize_categories
          workspace.categories.order(:display_order, :name).map do |category|
            portable_record(category, %w[name flow_kind budget_group color_token display_order archived_at created_at updated_at])
          end
        end

        def serialize_accounts
          {
            records: workspace.accounts.order(:name).map do |account|
              portable_record(
                account,
                %w[name institution_name kind active include_in_net_worth include_in_cash notes currency_code archived_at created_at updated_at]
              )
            end,
            balance_observations: workspace.balance_observations.order(:effective_through_at, :created_at).map do |observation|
              portable_record(
                observation,
                %w[observed_at effective_through_at balance available_balance currency_code source_kind status notes created_at updated_at],
                account_external_id: observation.account_id,
                source_import_batch_external_id: observation.source_import_batch_id,
                source_import_row_external_id: observation.source_import_row_id
              )
            end
          }
        end

        def serialize_planning_templates
          {
            records: workspace.planning_templates
              .includes(:payment_plan_term, :credit_card_payment_policy, recurrence_rule: :recurrence_months)
              .order(:name)
              .map { |template| serialize_template(template) }
          }
        end

        def serialize_template(template)
          portable_record(
            template,
            %w[name kind flow_kind budget_group default_amount currency_code active_from active_until notes archived_at created_at updated_at],
            category_external_id: template.category_id,
            source_account_external_id: template.source_account_id,
            destination_account_external_id: template.destination_account_id
          ).merge(
            recurrence_rule: serialize_recurrence_rule(template.recurrence_rule),
            payment_plan_term: serialize_payment_plan_term(template.payment_plan_term),
            credit_card_payment_policy: serialize_card_policy(template.credit_card_payment_policy)
          ).compact
        end

        def serialize_recurrence_rule(rule)
          return if rule.blank?

          portable_record(
            rule,
            %w[cadence interval_count anchor_on day_one day_two starts_on ends_on weekend_policy created_at updated_at]
          ).merge(months: rule.recurrence_months.order(:month_number).pluck(:month_number))
        end

        def serialize_payment_plan_term(term)
          return if term.blank?

          portable_record(term, %w[total_due opening_paid_adjustment monthly_target target_completion_on created_at updated_at])
        end

        def serialize_card_policy(policy)
          return if policy.blank?

          portable_record(
            policy,
            %w[due_day minimum_payment priority estimate_policy created_at updated_at],
            liability_account_external_id: policy.liability_account_id,
            payment_account_external_id: policy.payment_account_id
          )
        end

        def serialize_budget_months
          {
            periods: workspace.budget_periods.order(:starts_on).map do |period|
              portable_record(period, %w[starts_on currency_code state notes created_at updated_at])
            end,
            items: workspace.budget_items.order(:scheduled_on, :created_at).map do |item|
              portable_record(
                item,
                %w[flow_kind budget_group planned_amount currency_code scheduled_on state origin_kind name_snapshot payee_snapshot category_snapshot priority_classification notes voided_at void_reason created_at updated_at],
                budget_period_external_id: item.budget_period_id,
                category_external_id: item.category_id,
                recurring_occurrence_external_id: item.recurring_occurrence_id,
                intended_source_account_external_id: item.intended_source_account_id,
                intended_destination_account_external_id: item.intended_destination_account_id
              )
            end,
            recurring_occurrences: workspace.recurring_occurrences.order(:scheduled_on, :created_at).map do |occurrence|
              portable_record(
                occurrence,
                %w[scheduled_on slot_key state created_at updated_at],
                planning_template_external_id: occurrence.planning_template_id,
                budget_period_external_id: occurrence.budget_period_id,
                budget_item_external_id: occurrence.budget_item_id
              )
            end,
            month_closes: workspace.month_closes.order(:closed_at).map do |close|
              portable_record(
                close,
                %w[state calculation_version planned_income planned_outflow planned_net actual_income actual_outflow actual_net remaining_income remaining_outflow forecast_income forecast_outflow forecast_net income_variance outflow_variance unresolved_count unmatched_count calculation_input_digest closed_at created_at updated_at],
                budget_period_external_id: close.budget_period_id,
                reopens_month_close_external_id: close.reopens_month_close_id
              )
            end,
            month_close_item_snapshots: workspace.month_close_item_snapshots.order(:month_close_id, :scheduled_on, :created_at).map do |snapshot|
              portable_record(
                snapshot,
                %w[flow_kind budget_group name_snapshot category_snapshot scheduled_on planned_amount actual_amount remaining_amount currency_code created_at updated_at],
                month_close_external_id: snapshot.month_close_id,
                budget_item_external_id: snapshot.budget_item_id
              )
            end,
            month_close_transaction_snapshots: workspace.month_close_transaction_snapshots.order(:month_close_id, :effective_on, :created_at).map do |snapshot|
              portable_record(
                snapshot,
                %w[flow_kind origin_kind description_snapshot category_snapshot effective_on gross_amount allocated_amount currency_code created_at updated_at],
                month_close_external_id: snapshot.month_close_id,
                financial_transaction_external_id: snapshot.financial_transaction_id
              )
            end
          }
        end

        def serialize_account_activity
          {
            import_profiles: workspace.import_profiles.order(:name).map do |profile|
              portable_record(
                profile,
                %w[name parser_name parser_version header_row_number column_mapping amount_strategy fingerprint_version active created_at updated_at],
                account_external_id: profile.account_id
              )
            end,
            import_batches: workspace.import_batches.order(:created_at).map do |batch|
              portable_record(
                batch,
                %w[import_kind original_filename file_digest idempotency_key parser_version mapping_version fingerprint_version coverage_starts_on coverage_ends_on status row_count imported_count duplicate_count error_count redacted_metadata warnings committed_at failed_at failure_code reverted_at created_at updated_at],
                account_external_id: batch.account_id,
                import_profile_external_id: batch.import_profile_id
              )
            end,
            import_rows: workspace.import_rows.order(:import_batch_id, :row_number).map do |row|
              portable_record(
                row,
                %w[row_number provider_transaction_id fingerprint fingerprint_version raw_payload normalized_payload normalization_result status error_code error_message created_at updated_at],
                import_batch_external_id: row.import_batch_id,
                financial_transaction_external_id: row.financial_transaction_id
              )
            end,
            transactions: workspace.financial_transactions.order(:effective_on, :created_at).map do |transaction|
              portable_record(
                transaction,
                %w[effective_on posted_on description payee memo gross_amount currency_code flow_kind state origin_kind provider_transaction_id idempotency_key voided_at void_reason created_at updated_at],
                category_external_id: transaction.category_id,
                import_row_external_id: transaction.import_row_id,
                reversal_transaction_external_id: transaction.reversal_transaction_id
              )
            end,
            account_postings: workspace.account_postings.order(:financial_transaction_id, :sequence_number).map do |posting|
              portable_record(
                posting,
                %w[amount currency_code role sequence_number created_at updated_at],
                financial_transaction_external_id: posting.financial_transaction_id,
                account_external_id: posting.account_id
              )
            end,
            budget_allocations: workspace.budget_allocations.order(:created_at).map do |allocation|
              portable_record(
                allocation,
                %w[amount currency_code match_kind match_confidence matched_at created_at updated_at],
                budget_item_external_id: allocation.budget_item_id,
                financial_transaction_external_id: allocation.financial_transaction_id
              )
            end
          }
        end

        def portable_record(record, fields, references = {})
          attributes = record.attributes.slice(*fields)
          record.class.defined_enums.each_key do |enum_name|
            attributes[enum_name] = record.public_send(enum_name) if fields.include?(enum_name)
          end
          {
            external_id: record.id,
            attributes: Platform::CanonicalJson.normalize(attributes)
          }.merge(references.compact)
        end

        def checksum(payload)
          Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(payload))
        end

        def record_export!(payload)
          transfer = workspace.data_transfer_runs.create!(
            actor_membership: membership,
            operation: "export",
            payload_format_version: FORMAT_VERSION.to_s,
            envelope_version: Platform::UserDataBackupCodec::ENCRYPTED_FORMAT_VERSION.to_s,
            payload_checksum: payload.fetch(:payload_checksum),
            selected_scopes: scopes,
            state: "succeeded",
            result_counts: export_counts(payload.fetch(:data)),
            started_at: Time.current,
            completed_at: Time.current
          )
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: nil,
            entity: transfer,
            action: "backup_export",
            changed_fields: %i[state selected_scopes payload_format_version]
          )
        end

        def export_counts(data)
          data.each_with_object({}) do |(scope, value), counts|
            counts[scope.to_s] = if value.is_a?(Hash)
              value.values.sum { |records| records.is_a?(Array) ? records.size : 0 }
            else
              value.respond_to?(:size) ? value.size : 0
            end
          end
        end
      end
    end
  end
end
