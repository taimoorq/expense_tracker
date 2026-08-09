module Platform
  module Backup
    module V2
      class ExportJob < ApplicationJob
        include ActiveJob::Continuable

        class InvalidArtifact < StandardError; end

        queue_as :backups
        retry_on StandardError, wait: :polynomially_longer, attempts: 5, report: true do |job, error|
          job.send(:mark_exhausted_failure, error)
        end
        discard_on InvalidArtifact, report: true do |job, error|
          job.send(:mark_exhausted_failure, error)
        end

        def perform(operation_id, artifact_id)
          @operation = OperationRun.find(operation_id)
          @artifact = BackupExportArtifact.find(artifact_id)

          step :validate_artifact
          step :generate_export
          step :finalize_progress
        end

        private

        attr_reader :artifact, :operation

        def validate_artifact
          valid = artifact.operation_run_id == operation.id &&
            artifact.budget_workspace_id == operation.budget_workspace_id &&
            operation.job_arguments == [ artifact.id ]
          raise InvalidArtifact, "The queued export identity is invalid" unless valid

          operation.record_progress!(current: 1, total: 3, label: "Export request validated") unless operation.state_succeeded?
        end

        def generate_export
          exporter = Exporter.new(user: artifact.user, scopes: artifact.data_transfer_run.selected_scopes)
          payload = exporter.as_json
          password = artifact.export_password
          contents = Platform::UserDataBackupCodec.encode(payload: payload, password: password)
          outcome = Platform::Operations::Executor.call(
            workspace: artifact.budget_workspace,
            actor_membership: operation.actor_membership,
            operation_type: operation.operation_type,
            idempotency_key: operation.idempotency_key,
            request: artifact.operation_request,
            redacted_parameters: operation.redacted_parameters,
            retryable: true,
            on_replay: ->(reference) { BackupExportArtifact.find(reference.fetch("id")) }
          ) do |running_operation|
            artifact.write!(contents: contents, filename: exporter.filename(password: password))
            finish_transfer!(payload, running_operation)
            running_operation.record_progress!(current: 2, total: 3, label: "Backup file generated")
            Platform::Operations::Executor::Completion.new(
              value: artifact,
              result_counts: artifact.data_transfer_run.result_counts,
              result_reference: { "type" => "BackupExportArtifact", "id" => artifact.id }
            )
          end
          @operation = outcome.operation_run
        end

        def finish_transfer!(payload, running_operation)
          transfer = artifact.data_transfer_run
          transfer.update!(
            operation_run: running_operation,
            payload_checksum: payload.fetch(:payload_checksum),
            state: "succeeded",
            result_counts: Platform::Backup::PayloadCounts.call(payload.fetch(:data)),
            started_at: transfer.started_at || Time.current,
            completed_at: Time.current
          )
          Audit::Recorder.call(
            workspace: artifact.budget_workspace,
            actor_membership: operation.actor_membership,
            operation_run: running_operation,
            entity: transfer,
            action: "backup_export",
            changed_fields: %i[state selected_scopes payload_format_version]
          )
        end

        def finalize_progress
          operation.record_progress!(current: 3, total: 3, label: "Backup ready to download")
        end

        def mark_exhausted_failure(error)
          @operation ||= OperationRun.find_by(id: arguments.first)
          @artifact ||= BackupExportArtifact.find_by(id: arguments.second)
          artifact&.fail! if artifact&.state_pending?
          if artifact&.data_transfer_run && !artifact.data_transfer_run.state_succeeded?
            artifact.data_transfer_run.update!(
              state: "failed",
              completed_at: Time.current,
              error_code: error.class.name.underscore.tr("/", "_")
            )
          end
          return if operation.blank? || operation.state_succeeded?

          operation.update!(
            state: "failed",
            completed_at: Time.current,
            error_code: error.class.name.underscore.tr("/", "_")
          )
        end
      end
    end
  end
end
