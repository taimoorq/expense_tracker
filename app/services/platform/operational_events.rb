module Platform
  class OperationalEvents
    EVENT_FIELDS = {
      "operation.started" => %i[workspace_id operation_id operation_type retryable],
      "operation.replayed" => %i[workspace_id operation_id operation_type duration_ms],
      "operation.succeeded" => %i[workspace_id operation_id operation_type duration_ms result_count],
      "operation.failed" => %i[workspace_id operation_id operation_type duration_ms error_class retryable],
      "operation.queued" => %i[workspace_id operation_id operation_type job_class],
      "operation.enqueue_failed" => %i[workspace_id operation_id operation_type job_class error_class],
      "import.completed" => %i[workspace_id import_id account_id imported_count duplicate_count warning_count replayed],
      "import.failed" => %i[workspace_id account_id error_class],
      "backup_restore.succeeded" => %i[workspace_id transfer_id operation_id result_count replacement],
      "backup_restore.failed" => %i[workspace_id transfer_id error_class replacement],
      "shadow_read.mismatch" => %i[workspace_id comparison_type mismatch_count],
      "external_dependency.failed" => %i[dependency operation error_class],
      "legacy_association.accessed" => %i[owner_type association source_location]
    }.freeze

    def self.notify(event_name, **payload)
      event_name = event_name.to_s
      allowed_fields = EVENT_FIELDS.fetch(event_name) do
        raise ArgumentError, "Unknown operational event #{event_name.inspect}"
      end
      unexpected_fields = payload.keys - allowed_fields
      if unexpected_fields.any?
        raise ArgumentError, "Unexpected fields for #{event_name}: #{unexpected_fields.map(&:inspect).to_sentence}"
      end

      Rails.event.notify("finance_tracking.#{event_name}", payload, caller_depth: 2)
    end
  end
end
