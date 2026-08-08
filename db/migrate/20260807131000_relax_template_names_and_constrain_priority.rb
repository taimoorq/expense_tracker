class RelaxTemplateNamesAndConstrainPriority < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :planning_templates,
      name: "uidx_active_templates_workspace_name",
      algorithm: :concurrently,
      if_exists: true
    add_index :planning_templates,
      %i[budget_workspace_id kind name],
      algorithm: :concurrently,
      name: "index_templates_on_workspace_kind_name"
    add_check_constraint :budget_items,
      "priority_classification IS NULL OR priority_classification IN ('need', 'want', 'goal', 'unclassified')",
      name: "budget_items_priority_valid"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Template names cannot be made unique until legacy duplicates are resolved"
  end
end
