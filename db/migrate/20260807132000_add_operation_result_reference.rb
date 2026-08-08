class AddOperationResultReference < ActiveRecord::Migration[8.1]
  def change
    add_column :operation_runs, :result_reference, :jsonb, null: false, default: {}
  end
end
