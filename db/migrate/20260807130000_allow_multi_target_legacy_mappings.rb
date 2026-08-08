class AllowMultiTargetLegacyMappings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :legacy_record_mappings,
      name: "uidx_legacy_mappings_source",
      algorithm: :concurrently,
      if_exists: true
    add_index :legacy_record_mappings,
      %i[budget_workspace_id legacy_record_type legacy_record_id target_record_type],
      unique: true,
      algorithm: :concurrently,
      name: "uidx_legacy_mappings_source_target_type"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Multi-target legacy mappings cannot be contracted before migration completion"
  end
end
