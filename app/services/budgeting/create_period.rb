module Budgeting
  class CreatePeriod
    def self.call(workspace:, actor_membership:, starts_on:, idempotency_key:, notes: nil)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        starts_on: starts_on,
        idempotency_key: idempotency_key,
        notes: notes
      ).call
    end

    def initialize(workspace:, actor_membership:, starts_on:, idempotency_key:, notes:)
      @workspace = workspace
      @actor_membership = actor_membership
      @starts_on = starts_on.to_date.beginning_of_month
      @idempotency_key = idempotency_key
      @notes = notes
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "create_budget_period",
        idempotency_key: idempotency_key,
        request: { starts_on: starts_on, notes: notes },
        redacted_parameters: { "field_names" => %w[notes starts_on] },
        on_replay: ->(reference) { BudgetPeriod.find(reference.fetch("id")) }
      ) do |operation|
        period = BudgetPeriod.find_or_initialize_by(budget_workspace: workspace, starts_on: starts_on)
        created = period.new_record?
        period.assign_attributes(currency_code: workspace.default_currency_code, notes: notes, state: "open") if created
        period.save!
        if created
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: actor_membership,
            operation_run: operation,
            entity: period,
            action: "create",
            changed_fields: %i[starts_on currency_code notes]
          )
        end
        Platform::Operations::Executor::Completion.new(
          value: period,
          result_counts: { "budget_periods_created" => created ? 1 : 0 },
          result_reference: { "type" => "BudgetPeriod", "id" => period.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :idempotency_key, :notes, :starts_on, :workspace
  end
end
