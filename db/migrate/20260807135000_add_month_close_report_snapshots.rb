class AddMonthCloseReportSnapshots < ActiveRecord::Migration[8.1]
  def up
    change_table :month_closes, bulk: true do |table|
      table.decimal :remaining_income, precision: 19, scale: 4, null: false, default: 0
      table.decimal :remaining_outflow, precision: 19, scale: 4, null: false, default: 0
      table.decimal :forecast_income, precision: 19, scale: 4, null: false, default: 0
      table.decimal :forecast_outflow, precision: 19, scale: 4, null: false, default: 0
      table.decimal :income_variance, precision: 19, scale: 4, null: false, default: 0
      table.decimal :outflow_variance, precision: 19, scale: 4, null: false, default: 0
    end

    execute <<~SQL.squish
      UPDATE month_closes
      SET remaining_income = GREATEST(planned_income - actual_income, 0),
          remaining_outflow = GREATEST(planned_outflow - actual_outflow, 0),
          forecast_income = actual_income + GREATEST(planned_income - actual_income, 0),
          forecast_outflow = actual_outflow + GREATEST(planned_outflow - actual_outflow, 0),
          income_variance = actual_income - planned_income,
          outflow_variance = actual_outflow - planned_outflow
    SQL

    create_table :month_close_item_snapshots, id: :uuid do |table|
      table.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      table.references :month_close, type: :uuid, null: false, foreign_key: true
      table.references :budget_item, type: :uuid, null: false, foreign_key: true
      table.string :flow_kind, null: false
      table.string :budget_group, null: false
      table.string :name_snapshot
      table.string :category_snapshot
      table.date :scheduled_on
      table.decimal :planned_amount, precision: 19, scale: 4, null: false
      table.decimal :actual_amount, precision: 19, scale: 4, null: false, default: 0
      table.decimal :remaining_amount, precision: 19, scale: 4, null: false, default: 0
      table.string :currency_code, limit: 3, null: false
      table.timestamps

      table.index %i[month_close_id budget_item_id], unique: true, name: "uidx_close_item_snapshots_close_item"
      table.index %i[month_close_id flow_kind], name: "idx_close_item_snapshots_close_flow"
      table.check_constraint "flow_kind IN ('income', 'outflow', 'transfer')", name: "close_item_snapshots_flow_valid"
      table.check_constraint "planned_amount >= 0 AND actual_amount >= 0 AND remaining_amount >= 0", name: "close_item_snapshots_amounts_nonnegative"
      table.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "close_item_snapshots_currency_valid"
    end

    create_table :month_close_transaction_snapshots, id: :uuid do |table|
      table.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      table.references :month_close, type: :uuid, null: false, foreign_key: true
      table.references :financial_transaction, type: :uuid, null: false, foreign_key: true
      table.string :flow_kind, null: false
      table.string :origin_kind, null: false
      table.string :description_snapshot, null: false
      table.string :category_snapshot
      table.date :effective_on, null: false
      table.decimal :gross_amount, precision: 19, scale: 4, null: false
      table.decimal :allocated_amount, precision: 19, scale: 4, null: false, default: 0
      table.string :currency_code, limit: 3, null: false
      table.timestamps

      table.index %i[month_close_id financial_transaction_id], unique: true, name: "uidx_close_transaction_snapshots_close_transaction"
      table.index %i[month_close_id flow_kind category_snapshot], name: "idx_close_transaction_snapshots_reporting"
      table.check_constraint "flow_kind IN ('income', 'outflow', 'transfer', 'adjustment')", name: "close_transaction_snapshots_flow_valid"
      table.check_constraint "gross_amount >= 0 AND allocated_amount >= 0 AND allocated_amount <= gross_amount", name: "close_transaction_snapshots_amounts_valid"
      table.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "close_transaction_snapshots_currency_valid"
    end

    add_foreign_key :month_close_item_snapshots, :month_closes,
      column: %i[month_close_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_close_item_snapshots_close_workspace"
    add_foreign_key :month_close_item_snapshots, :budget_items,
      column: %i[budget_item_id budget_workspace_id currency_code],
      primary_key: %i[id budget_workspace_id currency_code],
      name: "fk_close_item_snapshots_item_currency"
    add_foreign_key :month_close_transaction_snapshots, :month_closes,
      column: %i[month_close_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_close_transaction_snapshots_close_workspace"
    add_foreign_key :month_close_transaction_snapshots, :financial_transactions,
      column: %i[financial_transaction_id budget_workspace_id currency_code],
      primary_key: %i[id budget_workspace_id currency_code],
      name: "fk_close_transaction_snapshots_transaction_currency"
  end

  def down
    drop_table :month_close_transaction_snapshots
    drop_table :month_close_item_snapshots
    remove_columns :month_closes,
      :remaining_income,
      :remaining_outflow,
      :forecast_income,
      :forecast_outflow,
      :income_variance,
      :outflow_variance
  end
end
