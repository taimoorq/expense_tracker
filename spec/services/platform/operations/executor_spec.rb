require "rails_helper"

RSpec.describe Platform::Operations::Executor do
  def execute(workspace:, membership:, request: { name: "Groceries" }, &block)
    described_class.call(
      workspace: workspace,
      actor_membership: membership,
      operation_type: "create_category",
      idempotency_key: "category-1",
      request: request,
      redacted_parameters: { "field_names" => [ "name" ] },
      on_replay: ->(reference) { Category.find(reference.fetch("id")) },
      &block
    )
  end

  it "commits a mutation and replays its result without rerunning the block" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    executions = 0
    command = lambda do |operation|
      executions += 1
      category = create(:category, budget_workspace: workspace, name: "Groceries")
      Audit::Recorder.call(
        workspace: workspace,
        actor_membership: membership,
        operation_run: operation,
        entity: category,
        action: "create",
        changed_fields: %i[name flow_kind]
      )
      described_class::Completion.new(
        value: category,
        result_counts: { "created" => 1 },
        result_reference: { "type" => "Category", "id" => category.id }
      )
    end

    first = execute(workspace: workspace, membership: membership, &command)
    replay = execute(workspace: workspace, membership: membership, &command)

    expect(executions).to eq(1)
    expect(first).not_to be_replayed
    expect(replay).to be_replayed
    expect(replay.value).to eq(first.value)
    expect(first.operation_run.reload).to be_state_succeeded
    expect(workspace.audit_events.count).to eq(1)
  end

  it "rejects reuse of an idempotency key for a different request" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    command = lambda do |_operation|
      category = create(:category, budget_workspace: workspace)
      described_class::Completion.new(
        value: category,
        result_counts: {},
        result_reference: { "type" => "Category", "id" => category.id }
      )
    end
    execute(workspace: workspace, membership: membership, &command)

    expect do
      execute(workspace: workspace, membership: membership, request: { name: "Utilities" }, &command)
    end.to raise_error(described_class::IdempotencyConflict)
    expect(workspace.categories.count).to eq(1)
  end

  it "rolls back command data and retains a redacted failed operation" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)

    expect do
      execute(workspace: workspace, membership: membership) do |_operation|
        create(:category, budget_workspace: workspace)
        raise ArgumentError, "forced rollback"
      end
    end.to raise_error(ArgumentError, "forced rollback")

    expect(workspace.categories).to be_empty
    operation = workspace.operation_runs.sole
    expect(operation).to be_state_failed
    expect(operation.error_code).to eq("argument_error")
    expect(operation.redacted_parameters).to eq("field_names" => [ "name" ])
  end

  it "emits structured lifecycle events without request or result payloads" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    command = lambda do |_operation|
      category = create(:category, budget_workspace: workspace)
      described_class::Completion.new(
        value: category,
        result_counts: { "created" => 1 },
        result_reference: { "type" => "Category", "id" => category.id }
      )
    end

    events = capture_rails_events do
      execute(workspace: workspace, membership: membership, &command)
      execute(workspace: workspace, membership: membership, &command)
    end

    operation_events = events.select { |event| event[:name].start_with?("finance_tracking.operation.") }
    expect(operation_events.map { |event| event[:name] }).to eq(
      %w[
        finance_tracking.operation.started
        finance_tracking.operation.succeeded
        finance_tracking.operation.replayed
      ]
    )
    expect(operation_events.second[:payload]).to include(result_count: 1)
    expect(operation_events.flat_map { |event| event[:payload].keys }).not_to include(:request, :result_reference)
  end
end
