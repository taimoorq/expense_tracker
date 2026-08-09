class StrengthenTargetStateCoherence < ActiveRecord::Migration[8.1]
  CONSTRAINTS = {
    budget_items: {
      name: "budget_items_void_state_coherent",
      expression: <<~SQL.squish
        (state = 'voided') =
        (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason) <> '')
      SQL
    },
    financial_transactions: {
      name: "transactions_void_state_coherent",
      expression: <<~SQL.squish
        (state = 'voided') =
        (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason) <> '')
      SQL
    },
    budget_workspaces: {
      name: "workspaces_closed_state_coherent",
      expression: "(status = 'closed') = (closed_at IS NOT NULL)"
    },
    workspace_memberships: {
      name: "memberships_removed_state_coherent",
      expression: "(status = 'removed') = (removed_at IS NOT NULL)"
    },
    operation_runs: {
      name: "operations_completion_state_coherent",
      expression: <<~SQL.squish
        (state IN ('succeeded', 'failed', 'reversed')) = (completed_at IS NOT NULL)
      SQL
    },
    data_transfer_runs: {
      name: "transfer_runs_completion_state_coherent",
      expression: "(state IN ('succeeded', 'failed')) = (completed_at IS NOT NULL)"
    },
    import_batches: {
      name: "import_batches_terminal_state_coherent",
      expression: <<~SQL.squish
        (status IN ('committed', 'reverting', 'reverted')) = (committed_at IS NOT NULL)
        AND (status = 'failed') = (failed_at IS NOT NULL)
        AND (status = 'reverted') = (reverted_at IS NOT NULL)
      SQL
    }
  }.freeze

  LEGACY_CONSTRAINTS = {
    budget_items: {
      name: "budget_items_void_coherent",
      expression: "state = 'voided' OR (voided_at IS NULL AND void_reason IS NULL)"
    },
    financial_transactions: {
      name: "transactions_void_coherent",
      expression: "state = 'voided' OR (voided_at IS NULL AND void_reason IS NULL)"
    },
    budget_workspaces: {
      name: "workspaces_closed_at_coherent",
      expression: "status = 'closed' OR closed_at IS NULL"
    },
    workspace_memberships: {
      name: "memberships_removed_at_coherent",
      expression: "status = 'removed' OR removed_at IS NULL"
    },
    operation_runs: {
      name: "operations_completion_coherent",
      expression: "state NOT IN ('succeeded', 'failed', 'reversed') OR completed_at IS NOT NULL"
    },
    data_transfer_runs: {
      name: "transfer_runs_completion_coherent",
      expression: "state NOT IN ('succeeded', 'failed') OR completed_at IS NOT NULL"
    }
  }.freeze

  IMPORT_BATCH_LEGACY_CONSTRAINTS = {
    "import_batches_commit_coherent" => "status <> 'committed' OR committed_at IS NOT NULL",
    "import_batches_failure_coherent" => "status <> 'failed' OR failed_at IS NOT NULL",
    "import_batches_revert_coherent" => "status <> 'reverted' OR reverted_at IS NOT NULL"
  }.freeze

  def up
    add_and_validate(CONSTRAINTS)
    remove_constraints(LEGACY_CONSTRAINTS)
    IMPORT_BATCH_LEGACY_CONSTRAINTS.each_key do |name|
      remove_check_constraint :import_batches, name: name, if_exists: true
    end
  end

  def down
    add_and_validate(LEGACY_CONSTRAINTS)
    IMPORT_BATCH_LEGACY_CONSTRAINTS.each do |name, expression|
      add_check_constraint :import_batches, expression, name: name, validate: false
      validate_check_constraint :import_batches, name: name
    end
    remove_constraints(CONSTRAINTS)
  end

  private

  def add_and_validate(constraints)
    constraints.each do |table_name, definition|
      add_check_constraint table_name,
        definition.fetch(:expression),
        name: definition.fetch(:name),
        validate: false
      validate_check_constraint table_name, name: definition.fetch(:name)
    end
  end

  def remove_constraints(constraints)
    constraints.each do |table_name, definition|
      remove_check_constraint table_name, name: definition.fetch(:name), if_exists: true
    end
  end
end
