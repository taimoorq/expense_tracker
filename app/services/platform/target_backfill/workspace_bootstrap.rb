require "digest"

module Platform
  module TargetBackfill
    class WorkspaceBootstrap
      VERSION = "target-v1".freeze
      DEFAULT_CURRENCY = "USD".freeze
      BATCH_SIZE = 1_000
      LEGACY_TABLES = [
        AccountActivity,
        AccountActivityImport,
        BudgetMonth,
        ExpenseEntry,
        PaySchedule,
        Subscription,
        MonthlyBill,
        PaymentPlan,
        CreditCard
      ].freeze

      Result = Data.define(:workspace, :membership, :operation_run, :assigned_counts) do
        def as_json(*)
          {
            workspace_id: workspace.id,
            membership_id: membership.id,
            operation_run_id: operation_run.id,
            assigned_counts: assigned_counts
          }
        end
      end

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        preflight_currency!
        workspace, membership, operation_run = bootstrap_records
        counts = assign_legacy_records(workspace)
        record_user_mapping(workspace)
        operation_run.update!(result_counts: operation_run.result_counts.merge("workspace_assignment" => counts))

        Result.new(
          workspace: workspace,
          membership: membership,
          operation_run: operation_run,
          assigned_counts: counts
        )
      end

      private

      attr_reader :user

      def bootstrap_records
        ApplicationRecord.transaction do
          provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
          workspace = provisioned.workspace
          membership = provisioned.membership
          operation_run = OperationRun.find_or_create_by!(
            budget_workspace: workspace,
            operation_type: "target_model_backfill",
            idempotency_key: VERSION
          ) do |record|
            record.request_digest = Digest::SHA256.hexdigest([ VERSION, user.id ].join(":"))
            record.redacted_parameters = { "version" => VERSION }
            record.state = "running"
            record.started_at = Time.current
          end
          unless operation_run.state_running? && operation_run.completed_at.blank?
            operation_run.update!(
              state: "running",
              started_at: Time.current,
              completed_at: nil,
              error_code: nil
            )
          end

          [ workspace, membership, operation_run ]
        end
      end

      def assign_legacy_records(workspace)
        counts = {}
        counts["accounts"] = assign_accounts(workspace)

        LEGACY_TABLES.each do |model|
          counts[model.table_name] = assign_model(model, workspace)
        end

        counts
      end

      def assign_accounts(workspace)
        foreign_workspace_count = user.accounts.where.not(budget_workspace_id: [ nil, workspace.id ]).count
        if foreign_workspace_count.positive?
          raise OwnershipMismatch, "#{foreign_workspace_count} accounts belong to another workspace"
        end

        update_in_batches(
          user.accounts.where(budget_workspace_id: nil).or(user.accounts.where(currency_code: nil)),
          budget_workspace_id: workspace.id,
          currency_code: workspace.default_currency_code
        )
      end

      def assign_model(model, workspace)
        update_in_batches(
          model.where(user_id: user.id, budget_workspace_id: nil),
          budget_workspace_id: workspace.id
        )
      end

      def update_in_batches(scope, attributes)
        scope.in_batches(of: BATCH_SIZE).sum { |batch| batch.update_all(attributes) }
      end

      def record_user_mapping(workspace)
        LegacyRecordMapping.find_or_create_by!(
          budget_workspace: workspace,
          legacy_record_type: "User",
          legacy_record_id: user.id
        ) do |mapping|
          mapping.target_record_type = "BudgetWorkspace"
          mapping.target_record_id = workspace.id
          mapping.mapping_version = VERSION
          mapping.status = "mapped"
          mapping.source_checksum = Digest::SHA256.hexdigest(user.id)
        end
      end

      def preflight_currency!
        mismatched = user.accounts.where.not(currency_code: [ nil, DEFAULT_CURRENCY ]).count
        raise CurrencyMismatch, "#{mismatched} accounts use another currency" if mismatched.positive?
      end

      class CurrencyMismatch < StandardError; end
      class OwnershipMismatch < StandardError; end
    end
  end
end
