require "digest"

module Budgeting
  class ClosePeriod
    def self.call(workspace:, actor_membership:, budget_period:, idempotency_key:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        budget_period: budget_period,
        idempotency_key: idempotency_key
      ).call
    end

    def initialize(workspace:, actor_membership:, budget_period:, idempotency_key:)
      @workspace = workspace
      @actor_membership = actor_membership
      @budget_period = budget_period
      @idempotency_key = idempotency_key
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise InvalidState, "budget period must belong to this workspace" unless budget_period.budget_workspace_id == workspace.id

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "close_budget_period",
        idempotency_key: idempotency_key,
        request: { budget_period_id: budget_period.id, calculation_version: PeriodSummary::CALCULATION_VERSION },
        redacted_parameters: { "field_names" => [ "budget_period_id" ] },
        retryable: true,
        on_replay: ->(reference) { MonthClose.find(reference.fetch("id")) }
      ) do |operation|
        budget_period.lock!
        raise InvalidState, "only an open or reopened period can be closed" unless budget_period.state_open? || budget_period.state_reopened?

        readiness = CloseReadiness.call(period: budget_period)
        close = MonthClose.create!(close_attributes(readiness, operation))
        snapshots = MonthCloseSnapshotWriter.call(month_close: close)
        budget_period.update!(state: "closed")
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: budget_period,
          action: "close",
          changed_fields: %i[state]
        )
        Platform::Operations::Executor::Completion.new(
          value: close,
          result_counts: {
            "month_closes" => 1,
            "month_close_item_snapshots" => snapshots.item_count,
            "month_close_transaction_snapshots" => snapshots.transaction_count
          },
          result_reference: { "type" => "MonthClose", "id" => close.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :budget_period, :idempotency_key, :workspace

    def close_attributes(readiness, operation)
      summary = readiness.summary
      {
        budget_workspace: workspace,
        budget_period: budget_period,
        closed_by_membership: actor_membership,
        close_operation: operation,
        state: "closed",
        calculation_version: PeriodSummary::CALCULATION_VERSION,
        planned_income: summary.planned_income,
        planned_outflow: summary.planned_outflow,
        planned_net: summary.planned_net,
        actual_income: summary.actual_income,
        actual_outflow: summary.actual_outflow,
        actual_net: summary.actual_net,
        remaining_income: summary.remaining_income,
        remaining_outflow: summary.remaining_outflow,
        forecast_income: summary.forecast_income,
        forecast_outflow: summary.forecast_outflow,
        forecast_net: summary.forecast_net,
        income_variance: summary.income_variance,
        outflow_variance: summary.outflow_variance,
        unresolved_count: readiness.unresolved_account_count,
        unmatched_count: readiness.unmatched_count,
        calculation_input_digest: calculation_input_digest,
        closed_at: Time.current
      }
    end

    def calculation_input_digest
      inputs = {
        period: [ budget_period.id, budget_period.lock_version ],
        items: budget_period.budget_items.order(:id).pluck(:id, :lock_version),
        allocations: workspace.budget_allocations
          .joins(:budget_item)
          .where(budget_items: { budget_period_id: budget_period.id })
          .order(:id)
          .pluck(:id, :lock_version),
        transactions: workspace.financial_transactions
          .where(effective_on: budget_period.starts_on..budget_period.starts_on.end_of_month)
          .order(:id)
          .pluck(:id, :lock_version)
      }
      Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(inputs))
    end

    class InvalidState < StandardError; end
  end
end
