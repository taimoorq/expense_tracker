require "digest"

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
        @request_digest = Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(request))
        @redacted_parameters = redacted_parameters
        @retryable = retryable
        @on_replay = on_replay
      end

      def call
        operation = nil
        ApplicationRecord.transaction do
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
      rescue IdempotencyConflict
        raise
      rescue StandardError => error
        record_failure(error)
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
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        nil
      end

      class IdempotencyConflict < StandardError; end
    end
  end
end
