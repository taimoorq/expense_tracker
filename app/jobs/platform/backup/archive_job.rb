require "digest"

module Platform
  module Backup
    class ArchiveJob < ApplicationJob
      include ActiveJob::Continuable

      class InvalidArchive < StandardError; end

      queue_as :backups
      limits_concurrency(
        key: ->(operation_id, *) { OperationRun.find(operation_id).budget_workspace_id },
        to: 1,
        group: "workspace_backup_archives",
        duration: 4.hours
      )
      retry_on StandardError, wait: :polynomially_longer, attempts: 5, report: true do |job, error|
        job.send(:mark_exhausted_failure, error)
      end
      discard_on InvalidArchive, report: true do |job, error|
        job.send(:mark_exhausted_failure, error)
      end

      def perform(operation_id, archive_id)
        @operation = OperationRun.find(operation_id)
        @archive = BackupArchive.find(archive_id)
        @configuration = ArchiveConfiguration.current

        step :validate_archive
        step :store_and_verify
        step :finalize_progress
      end

      private

      attr_reader :archive, :configuration, :operation

      def validate_archive
        valid = archive.operation_run_id == operation.id &&
          archive.budget_workspace_id == operation.budget_workspace_id &&
          operation.job_arguments == [ archive.id ]
        raise InvalidArchive, "The queued archive identity is invalid" unless valid

        membership = archive.actor_membership
        unless membership.status_active? && membership.role_owner? && archive.budget_workspace.status_active?
          raise InvalidArchive, "The archive owner or workspace is no longer active"
        end
        raise InvalidArchive, configuration.error unless configuration.ready?
        unless configuration.driver == archive.storage_adapter
          raise InvalidArchive, "The configured backup storage driver changed before the archive completed"
        end
        unless configuration.key_for(archive.encryption_key_id)
          raise InvalidArchive, "The archive encryption key is no longer configured"
        end

        unless operation.state_succeeded?
          operation.update!(
            state: "running",
            started_at: operation.started_at || Time.current,
            progress_current: 1,
            progress_total: 4,
            progress_label: "Archive request validated",
            last_heartbeat_at: Time.current
          )
        end
      end

      def store_and_verify
        return if archive.state_ready? && operation.state_succeeded?

        storage = Storage.build(configuration)
        if archive.state_writing?
          existing = storage.read(archive.storage_key)
          if existing
            verify_and_finalize!(existing)
            return
          end
          archive.reset_unwritten!
        end

        payload = ArchivePayload.export(
          user: archive.actor_membership.user,
          scopes: archive.data_transfer_run.selected_scopes,
          version: archive.payload_format_version
        )
        contents = ArchiveCodec.encode(
          payload: payload,
          configuration: configuration,
          key_id: archive.encryption_key_id
        )
        archive_checksum = Digest::SHA256.hexdigest(contents)
        archive.begin_writing!(
          payload_checksum: payload.fetch(:payload_checksum),
          archive_checksum: archive_checksum,
          byte_size: contents.bytesize
        )
        operation.record_progress!(current: 2, total: 4, label: "Encrypted archive prepared")

        storage.write(key: archive.storage_key, contents: contents, checksum: archive_checksum)
        persisted_contents = storage.read(archive.storage_key)
        raise Storage::Error, "The archive disappeared before verification" unless persisted_contents

        verify_and_finalize!(persisted_contents)
      end

      def verify_and_finalize!(contents)
        unless contents.bytesize == archive.byte_size && Digest::SHA256.hexdigest(contents) == archive.archive_checksum
          raise InvalidArchive, "The stored archive does not match its durable metadata"
        end

        decoded = Platform::UserDataBackupCodec.decode(
          source: contents,
          archive_configuration: configuration
        )
        raise InvalidArchive, decoded.fetch(:error) unless decoded[:success]

        payload = decoded.fetch(:payload)
        unless payload.fetch(:payload_checksum) == archive.payload_checksum
          raise InvalidArchive, "The stored archive payload checksum changed"
        end
        ArchivePayload.validate!(
          payload: payload,
          expected_version: archive.payload_format_version,
          scopes: archive.data_transfer_run.selected_scopes
        )

        finalize_success!(payload)
        PruneArchivesJob.perform_later(archive.budget_workspace_id)
      end

      def finalize_success!(payload)
        ApplicationRecord.transaction do
          archive.lock!
          unless archive.state_ready?
            archive.mark_ready!(
              payload_checksum: payload.fetch(:payload_checksum),
              archive_checksum: archive.archive_checksum,
              byte_size: archive.byte_size
            )
          end
          transfer = archive.data_transfer_run
          counts = Platform::Backup::PayloadCounts.call(payload.fetch(:data))
          unless transfer.state_succeeded?
            transfer.update!(
              payload_checksum: payload.fetch(:payload_checksum),
              state: "succeeded",
              result_counts: counts,
              started_at: transfer.started_at || archive.started_at || Time.current,
              completed_at: Time.current
            )
            Audit::Recorder.call(
              workspace: archive.budget_workspace,
              actor_membership: archive.actor_membership,
              operation_run: operation,
              entity: transfer,
              action: "backup_export",
              changed_fields: %i[state selected_scopes payload_format_version]
            )
          end
          operation.update!(
            state: "succeeded",
            progress_current: 3,
            progress_total: 4,
            progress_label: "Archive stored and verified",
            result_counts: counts,
            result_reference: { "type" => "BackupArchive", "id" => archive.id },
            completed_at: operation.completed_at || Time.current,
            error_code: nil,
            last_heartbeat_at: Time.current
          )
          record_schedule_success!
        end
        Platform::OperationalEvents.notify(
          "backup_archive.succeeded",
          workspace_id: archive.budget_workspace_id,
          archive_id: archive.id,
          operation_id: operation.id,
          byte_size: archive.byte_size,
          trigger: archive.trigger
        )
      end

      def record_schedule_success!
        return unless archive.backup_schedule

        archive.backup_schedule.update!(
          last_succeeded_at: Time.current,
          last_failed_at: nil,
          last_error_code: nil
        )
      end

      def finalize_progress
        operation.record_progress!(current: 4, total: 4, label: "Automatic backup ready")
      end

      def mark_exhausted_failure(error)
        @operation ||= OperationRun.find_by(id: arguments.first)
        @archive ||= BackupArchive.find_by(id: arguments.second)
        error_code = error.class.name.underscore.tr("/", "_")
        archive&.fail!(error_code: error_code) if archive && !archive.state_ready? && !archive.state_failed?
        if archive&.data_transfer_run && !archive.data_transfer_run.state_succeeded?
          archive.data_transfer_run.update!(
            state: "failed",
            completed_at: Time.current,
            error_code: error_code
          )
        end
        archive&.backup_schedule&.update!(
          last_failed_at: Time.current,
          last_error_code: error_code
        )
        if archive
          Platform::OperationalEvents.notify(
            "backup_archive.failed",
            workspace_id: archive.budget_workspace_id,
            archive_id: archive.id,
            operation_id: operation&.id,
            error_class: error.class.name,
            trigger: archive.trigger
          )
        end
        return if operation.blank? || operation.state_succeeded?

        operation.update!(
          state: "failed",
          completed_at: Time.current,
          error_code: error_code
        )
      end
    end
  end
end
