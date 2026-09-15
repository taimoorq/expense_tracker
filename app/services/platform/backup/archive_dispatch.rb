module Platform
  module Backup
    class ArchiveDispatch
      Result = Data.define(:operation, :archive)
      OPERATION_TYPE = "backup_archive".freeze
      JOB_CLASS = "Platform::Backup::ArchiveJob".freeze

      class Unavailable < StandardError; end
      class AlreadyInProgress < StandardError; end

      def self.call(user:, schedule: nil, scheduled_for: nil, configuration: ArchiveConfiguration.current)
        new(
          user: user,
          schedule: schedule,
          scheduled_for: scheduled_for,
          configuration: configuration
        ).call
      end

      def initialize(user:, schedule:, scheduled_for:, configuration:)
        @user = user
        @schedule = schedule
        @scheduled_for = scheduled_for
        @configuration = configuration
      end

      def call
        raise Unavailable, configuration.error unless configuration.ready?

        workspace = user.legacy_owned_budget_workspace
        raise Unavailable, "This workspace is not available for automatic backups." unless workspace

        membership = workspace.workspace_memberships.status_active.role_owner.find_by!(user: user)
        validate_schedule!(workspace)
        return existing_result if existing_archive
        raise AlreadyInProgress, "A backup is already in progress for this workspace." if workspace.backup_archives.active.exists?

        create_dispatch(workspace, membership)
      rescue ActiveRecord::RecordNotUnique, Platform::Operations::Executor::IdempotencyConflict
        return existing_result if existing_archive

        raise AlreadyInProgress, "A backup is already in progress for this workspace."
      end

      private

      attr_reader :configuration, :schedule, :scheduled_for, :user

      def create_dispatch(workspace, membership)
        archive_id = SecureRandom.uuid
        payload_format_version = ArchivePayload.version_for(workspace)
        operation = Platform::Operations::Dispatcher.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: OPERATION_TYPE,
          idempotency_key: idempotency_key,
          request: request(archive_id),
          redacted_parameters: {
            "format_version" => payload_format_version,
            "scopes" => Platform::UserDataExport::SCOPES,
            "trigger" => trigger,
            "scheduled_for" => scheduled_for&.iso8601,
            "storage_adapter" => configuration.driver,
            "envelope_version" => ArchiveCodec::VERSION,
            "encryption_key_id" => configuration.primary_key_id
          },
          job_class: JOB_CLASS,
          job_arguments: [],
          retryable: true
        ) do |operation_run|
          transfer = workspace.data_transfer_runs.create!(
            actor_membership: membership,
            operation_run: operation_run,
            operation: "export",
            payload_format_version: payload_format_version.to_s,
            envelope_version: ArchiveCodec::VERSION.to_s,
            payload_checksum: "0" * 64,
            selected_scopes: Platform::UserDataExport::SCOPES,
            state: "pending",
            result_counts: {}
          )
          archive = workspace.backup_archives.create!(
            id: archive_id,
            backup_schedule: schedule,
            actor_membership: membership,
            operation_run: operation_run,
            data_transfer_run: transfer,
            trigger: trigger,
            scheduled_for: scheduled_for,
            storage_adapter: configuration.driver,
            storage_key: storage_key(workspace, archive_id),
            filename: filename,
            payload_format_version: payload_format_version.to_s,
            envelope_version: ArchiveCodec::VERSION.to_s,
            encryption_key_id: configuration.primary_key_id
          )
          operation_run.update!(job_arguments: [ archive.id ])
        end
        Result.new(operation: operation, archive: operation.backup_archive)
      end

      def existing_result
        Result.new(operation: existing_archive.operation_run, archive: existing_archive)
      end

      def existing_archive
        return unless schedule && scheduled_for

        @existing_archive ||= schedule.backup_archives.find_by(scheduled_for: scheduled_for)
      end

      def validate_schedule!(workspace)
        if schedule.present?
          valid = schedule.budget_workspace_id == workspace.id && scheduled_for.present?
          raise Unavailable, "The scheduled backup identity is invalid." unless valid
        elsif scheduled_for.present?
          raise Unavailable, "A manual backup cannot have a scheduled slot."
        end
      end

      def idempotency_key
        schedule ? "scheduled:#{schedule.id}:#{scheduled_for.utc.iso8601}" : SecureRandom.uuid
      end

      def request(archive_id)
        {
          archive_id: archive_id,
          schedule_id: schedule&.id,
          scheduled_for: scheduled_for&.iso8601,
          trigger: trigger,
          scopes: Platform::UserDataExport::SCOPES,
          storage_adapter: configuration.driver,
          encryption_key_id: configuration.primary_key_id
        }
      end

      def storage_key(workspace, archive_id)
        timestamp = (scheduled_for || Time.current).utc.strftime("%Y/%m/%Y%m%dT%H%M%SZ")
        "workspaces/#{workspace.id}/#{timestamp}-#{archive_id}.json"
      end

      def filename
        timestamp = (scheduled_for || Time.current).utc.strftime("%Y%m%d-%H%M%S")
        "finance-tracking-automatic-backup-#{timestamp}-encrypted.json"
      end

      def trigger
        schedule ? "scheduled" : "manual"
      end
    end
  end
end
