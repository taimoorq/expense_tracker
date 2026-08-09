module Platform
  module Operations
    class Dispatcher
      def self.call(**attributes, &block)
        new(**attributes).call(&block)
      end

      def self.enqueue(operation)
        new(
          workspace: operation.budget_workspace,
          actor_membership: operation.actor_membership,
          operation_type: operation.operation_type,
          idempotency_key: operation.idempotency_key,
          request: nil,
          redacted_parameters: operation.redacted_parameters,
          job_class: operation.job_class,
          job_arguments: operation.job_arguments,
          retryable: operation.retryable?
        ).send(:enqueue, operation)
      end

      def initialize(workspace:, actor_membership:, operation_type:, idempotency_key:, request:,
        redacted_parameters:, job_class:, job_arguments:, retryable: true)
        @workspace = workspace
        @actor_membership = actor_membership
        @operation_type = operation_type
        @idempotency_key = idempotency_key
        @request_digest = RequestDigest.for(request) if request
        @redacted_parameters = redacted_parameters
        @job_class = job_class.to_s
        @job_arguments = Array(job_arguments)
        @retryable = retryable
      end

      def call
        operation = prepare_operation { |record| yield(record) if block_given? }
        enqueue(operation)
        operation
      end

      private

      attr_reader :actor_membership, :idempotency_key, :job_arguments, :job_class,
        :operation_type, :redacted_parameters, :request_digest, :retryable, :workspace

      def prepare_operation
        ApplicationRecord.transaction do
          operation = find_or_create_operation
          operation.lock!
          verify_request!(operation)
          verify_job!(operation)
          reset_for_retry!(operation)
          yield(operation) if block_given?
          operation
        end
      end

      def find_or_create_operation
        workspace.operation_runs.find_or_create_by!(
          operation_type: operation_type,
          idempotency_key: idempotency_key
        ) do |operation|
          operation.assign_attributes(
            actor_membership: actor_membership,
            request_digest: request_digest,
            redacted_parameters: redacted_parameters,
            retryable: retryable,
            state: "pending",
            job_class: job_class,
            job_arguments: job_arguments
          )
        end
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def verify_request!(operation)
        return if request_digest.blank? || operation.request_digest == request_digest

        raise Executor::IdempotencyConflict, "The idempotency key was already used for a different request"
      end

      def verify_job!(operation)
        expected = [ job_class, job_arguments ]
        actual = [ operation.job_class, operation.job_arguments ]
        return if actual == expected

        raise Executor::IdempotencyConflict, "The idempotency key was already assigned to a different job"
      end

      def reset_for_retry!(operation)
        return unless operation.state_failed? && operation.retryable?

        operation.update!(
          state: "pending",
          completed_at: nil,
          error_code: nil,
          enqueued_at: nil,
          last_enqueue_attempt_at: nil
        )
      end

      def enqueue(operation)
        operation.with_lock do
          return operation unless operation.state_pending?
          return operation if operation.enqueued_at.present?
          if operation.last_enqueue_attempt_at&.after?(1.minute.ago)
            return operation
          end

          operation.update!(last_enqueue_attempt_at: Time.current)
        end
        JobRegistry.fetch(operation.job_class).perform_later(operation.id, *operation.job_arguments)
        operation.with_lock do
          operation.update!(enqueued_at: Time.current)
        end
        Platform::OperationalEvents.notify(
          "operation.queued",
          workspace_id: operation.budget_workspace_id,
          operation_id: operation.id,
          operation_type: operation.operation_type,
          job_class: operation.job_class
        )
        operation
      rescue StandardError => error
        Rails.error.report(
          error,
          handled: true,
          context: { operation_id: operation.id, operation_type: operation.operation_type }
        )
        Platform::OperationalEvents.notify(
          "operation.enqueue_failed",
          workspace_id: operation.budget_workspace_id,
          operation_id: operation.id,
          operation_type: operation.operation_type,
          job_class: operation.job_class,
          error_class: error.class.name
        )
        operation
      end
    end
  end
end
