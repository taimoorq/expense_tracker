require "digest"

module Platform
  module Backup
    class RestoreCoordinator
      def self.call(user:, payload:, scopes:, replace_existing: false, checkpoint: nil, rollback: false)
        new(
          user: user,
          payload: payload,
          scopes: scopes,
          replace_existing: replace_existing,
          checkpoint: checkpoint,
          rollback: rollback
        ).call
      end

      def initialize(user:, payload:, scopes:, replace_existing:, checkpoint:, rollback:)
        @user = user
        @payload = payload.to_h.deep_symbolize_keys
        @scopes = Array(scopes).map(&:to_s) & Platform::UserDataExport::SCOPES
        @replace_existing = replace_existing
        @checkpoint = checkpoint
        @rollback = rollback
      end

      def call
        case payload.fetch(:version).to_i
        when 1 then restore_v1
        when 2 then restore_v2
        else { success: false, error: "This backup version is not supported." }
        end
      end

      private

      attr_reader :checkpoint, :payload, :replace_existing, :rollback, :scopes, :user

      def restore_v1
        provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
        workspace = provisioned.workspace
        membership = provisioned.membership
        replacing = ReplacementState.any?(user: user, scopes: scopes)
        recovery = checkpoint || (CreateCheckpoint.call(user: user, scopes: scopes) if replacing)
        validate_target_v1_scope!(workspace)
        checksum = Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(payload))
        transfer = start_transfer(workspace, membership, checksum, "1", recovery)

        outcome = Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "backup_v1_restore",
          idempotency_key: "#{checksum}:#{recovery&.id || 'empty'}",
          request: { payload_checksum: checksum, scopes: scopes, checkpoint_id: recovery&.id },
          redacted_parameters: { "format_version" => 1, "scopes" => scopes },
          retryable: true,
          on_replay: ->(reference) { DataTransferRun.find(reference.fetch("id")) }
        ) do |operation|
          transfer.update!(operation_run: operation)
          target_cutover = workspace.target_reads_enabled?
          ReplacementCleaner.call(user: user, workspace: workspace) if target_cutover
          result = Platform::Backup::V1::Importer.new(user: user, payload: payload, scopes: scopes).call
          raise RestoreFailed, result.fetch(:error) unless result[:success]

          restore_target_after_v1!(workspace) if target_cutover
          finish_transfer(transfer, operation, result.fetch(:counts), recovery)
          Platform::Operations::Executor::Completion.new(
            value: transfer,
            result_counts: result.fetch(:counts),
            result_reference: { "type" => "DataTransferRun", "id" => transfer.id }
          )
        end
        finish_rollback!(workspace, membership, outcome.operation_run, recovery) if rollback
        { success: true, counts: outcome.value.result_counts, checkpoint_id: recovery&.id }
      rescue RestoreFailed, ActiveRecord::RecordInvalid, ArgumentError => error
        fail_transfer(transfer, error)
        { success: false, error: error.message }
      end

      def restore_v2
        prior = prior_v2_success unless replace_existing || rollback
        return { success: true, counts: prior.result_counts } if prior

        replacing = ReplacementState.any?(user: user, scopes: scopes)
        unless !replacing || replace_existing || rollback
          return { success: false, error: "Backup V2 requires an empty destination unless you confirm an automatic recovery checkpoint first." }
        end
        recovery = checkpoint || (CreateCheckpoint.call(user: user, scopes: scopes) if replacing)
        result = Platform::Backup::V2::Importer.new(
          user: user,
          payload: payload,
          scopes: scopes,
          replace_existing: replacing,
          checkpoint: recovery
        ).call
        if result[:success] && rollback
          workspace = BudgetWorkspace.find_by!(legacy_owner_user_id: user.id)
          operation = workspace.operation_runs.where(operation_type: "backup_v2_restore").order(created_at: :desc).first
          finish_rollback!(workspace, workspace.workspace_memberships.find_by!(user: user), operation, recovery)
        end
        recovery.present? ? result.merge(checkpoint_id: recovery.id) : result
      end

      def prior_v2_success
        workspace = BudgetWorkspace.find_by(legacy_owner_user_id: user.id)
        return if workspace.blank?

        workspace.data_transfer_runs
          .operation_restore
          .state_succeeded
          .find_by(payload_checksum: payload[:payload_checksum])
      end

      def validate_target_v1_scope!(workspace)
        return unless workspace.target_reads_enabled?
        return if (Platform::Backup::V2::Preview::FINANCIAL_SCOPES - scopes).empty?

        raise ArgumentError, "A V1 restore into a target-backed budget must include all financial sections."
      end

      def restore_target_after_v1!(workspace)
        result = Platform::TargetBackfill::Runner.call(user: user)
        raise RestoreFailed, "The restored V1 data did not pass target-model verification." unless result.success?

        workspace.reload.update!(target_writes_enabled: true, target_reads_enabled: true)
      end

      def start_transfer(workspace, membership, checksum, version, recovery)
        workspace.data_transfer_runs.create!(
          actor_membership: membership,
          operation: "restore",
          payload_format_version: version,
          envelope_version: Platform::UserDataBackupCodec::ENCRYPTED_FORMAT_VERSION.to_s,
          payload_checksum: checksum,
          selected_scopes: scopes,
          checkpoint_reference: recovery&.id&.to_s || "empty-target",
          state: "running",
          result_counts: {},
          started_at: Time.current
        )
      end

      def finish_transfer(transfer, operation, counts, recovery)
        transfer.update!(
          operation_run: operation,
          checkpoint_reference: recovery&.id&.to_s || "empty-target",
          state: "succeeded",
          result_counts: counts,
          completed_at: Time.current
        )
        Audit::Recorder.call(
          workspace: transfer.budget_workspace,
          actor_membership: transfer.actor_membership,
          operation_run: operation,
          entity: transfer,
          action: "backup_restore",
          changed_fields: %i[state selected_scopes payload_format_version checkpoint_reference]
        )
      end

      def fail_transfer(transfer, error)
        return if transfer.blank? || !transfer.persisted?

        transfer.update!(
          state: "failed",
          error_code: error.class.name.underscore.tr("/", "_"),
          completed_at: Time.current
        )
      rescue ActiveRecord::RecordInvalid
        nil
      end

      def finish_rollback!(workspace, membership, operation, recovery)
        recovery.update!(state: "restored", restored_at: Time.current)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: recovery,
          action: "restore_rollback",
          changed_fields: %i[state restored_at]
        )
      end

      class RestoreFailed < StandardError; end
    end
  end
end
