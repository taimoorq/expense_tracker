module Platform
  module Operations
    class ReconcileDispatchesJob < ApplicationJob
      queue_as :maintenance

      STALE_AFTER = 1.minute

      def perform
        OperationRun
          .where(state: "pending", enqueued_at: nil)
          .where.not(job_class: nil)
          .where("last_enqueue_attempt_at IS NULL OR last_enqueue_attempt_at < ?", STALE_AFTER.ago)
          .find_each do |operation|
            Dispatcher.enqueue(operation)
          end
      end
    end
  end
end
