module Platform
  module Backup
    module V2
      class ExportDispatch
        Result = Data.define(:operation, :artifact)
        OPERATION_TYPE = "backup_v2_export".freeze
        JOB_CLASS = "Platform::Backup::V2::ExportJob".freeze

        def self.call(user:, scopes:, password: nil)
          new(user: user, scopes: scopes, password: password).call
        end

        def initialize(user:, scopes:, password: nil)
          @user = user
          @scopes = Array(scopes).map(&:to_s) & Platform::UserDataExport::SCOPES
          @password = password.presence
        end

        def call
          workspace = user.legacy_owned_budget_workspace
          membership = workspace.workspace_memberships.status_active.find_by!(user: user)
          generation_key = SecureRandom.uuid
          artifact = nil
          operation = Platform::Operations::Dispatcher.call(
            workspace: workspace,
            actor_membership: membership,
            operation_type: OPERATION_TYPE,
            idempotency_key: generation_key,
            request: { generation_key: generation_key, scopes: scopes },
            redacted_parameters: { "format_version" => 2, "scopes" => scopes },
            job_class: JOB_CLASS,
            job_arguments: [],
            retryable: true
          ) do |operation_run|
            transfer = workspace.data_transfer_runs.create!(
              actor_membership: membership,
              operation_run: operation_run,
              operation: "export",
              payload_format_version: "2",
              envelope_version: Platform::UserDataBackupCodec::ENCRYPTED_FORMAT_VERSION.to_s,
              payload_checksum: "0" * 64,
              selected_scopes: scopes,
              state: "pending",
              result_counts: {}
            )
            artifact = user.backup_export_artifacts.create!(
              budget_workspace: workspace,
              operation_run: operation_run,
              data_transfer_run: transfer,
              generation_key: generation_key,
              encrypted_export_password: encoded_password,
              expires_at: BackupExportArtifact::RETENTION.from_now
            )
            operation_run.job_arguments = [ artifact.id ]
            operation_run.save!
          end
          Result.new(operation: operation, artifact: artifact || operation.backup_export_artifact)
        end

        private

        attr_reader :password, :scopes, :user

        def encoded_password
          Platform::Backup::RestoreDraftCodec.encode(password: password) if password
        end
      end
    end
  end
end
