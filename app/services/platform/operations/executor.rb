module Platform
  module Operations
    class Executor
      Completion = Data.define(:value, :result_counts, :result_reference)
      Outcome = Data.define(:operation_run, :value, :replayed) do
        def replayed?
          replayed
        end
      end

      def self.call(workspace:, actor_membership:, operation_type:, idempotency_key:, request:, redacted_parameters: {}, retryable: false, on_replay:, &block)
        new(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_type: operation_type,
          idempotency_key: idempotency_key,
          request: request,
          redacted_parameters: redacted_parameters,
          retryable: retryable,
          on_replay: on_replay
        ).call(&block)
      end

      def initialize(workspace:, actor_membership:, operation_type:, idempotency_key:, request:, redacted_parameters:, retryable:, on_replay:)
        @workspace = workspace
        @actor_membership = actor_membership
        @operation_type = operation_type
        @idempotency_key = idempotency_key
        @request_digest = RequestDigest.for(request)
        @redacted_parameters = redacted_parameters
        @retryable = retryable
        @on_replay = on_replay
      end

      def call
        monotonic_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        operation = nil
        outcome = ApplicationRecord.transaction do
          operation = find_or_create_operation
          operation.lock!
          verify_request!(operation)

          if operation.state_succeeded?
            next Outcome.new(
              operation_run: operation,
              value: on_replay.call(operation.result_reference),
              replayed: true
            )
          end

          operation.update!(state: "running", started_at: Time.current, completed_at: nil, error_code: nil)
          report_started(operation)
          completion = yield(operation)
          operation.update!(
            state: "succeeded",
            result_counts: completion.result_counts,
            result_reference: completion.result_reference,
            completed_at: Time.current,
            error_code: nil
          )
          Outcome.new(operation_run: operation, value: completion.value, replayed: false)
        end
        report_outcome(outcome, duration_ms(monotonic_started_at))
        outcome
      rescue IdempotencyConflict
        raise
      rescue StandardError => error
        failed_operation = record_failure(error)
        report_failure(failed_operation || operation, error, duration_ms(monotonic_started_at))
        raise
      end

      private

      attr_reader :actor_membership, :idempotency_key, :on_replay, :operation_type,
        :redacted_parameters, :request_digest, :retryable, :workspace

      def find_or_create_operation
        workspace.operation_runs.find_or_create_by!(
          operation_type: operation_type,
          idempotency_key: idempotency_key
        ) do |operation|
          operation.actor_membership = actor_membership
          operation.request_digest = request_digest
          operation.redacted_parameters = redacted_parameters
          operation.retryable = retryable
          operation.state = "running"
          operation.started_at = Time.current
        end
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def verify_request!(operation)
        operation.retryable = retryable if retryable && !operation.retryable?
        return if operation.request_digest == request_digest

        raise IdempotencyConflict, "The idempotency key was already used for a different request"
      end

      def record_failure(error)
        operation = find_or_create_operation
        operation.with_lock do
          operation.update!(
            state: "failed",
            completed_at: Time.current,
            error_code: error.class.name.underscore.tr("/", "_")
          )
        end
        operation
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        nil
      end

      def report_started(operation)
        Platform::OperationalEvents.notify(
          "operation.started",
          workspace_id: workspace.id,
          operation_id: operation.id,
          operation_type: operation_type,
          retryable: operation.retryable?
        )
      end

      def report_outcome(outcome, elapsed_ms)
        operation = outcome.operation_run
        event_name = outcome.replayed? ? "operation.replayed" : "operation.succeeded"
        payload = {
          workspace_id: workspace.id,
          operation_id: operation.id,
          operation_type: operation_type,
          duration_ms: elapsed_ms
        }
        payload[:result_count] = operation.result_counts.values.grep(Numeric).sum unless outcome.replayed?
        Platform::OperationalEvents.notify(event_name, **payload)
      end

      def report_failure(operation, error, elapsed_ms)
        Platform::OperationalEvents.notify(
          "operation.failed",
          workspace_id: workspace.id,
          operation_id: operation&.id,
          operation_type: operation_type,
          duration_ms: elapsed_ms,
          error_class: error.class.name,
          retryable: operation&.retryable? || retryable
        )
      end

      def duration_ms(monotonic_started_at)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_started_at) * 1_000).round
      end

      class IdempotencyConflict < StandardError; end
    end
  end
end
