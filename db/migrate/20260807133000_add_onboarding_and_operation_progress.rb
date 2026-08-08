class AddOnboardingAndOperationProgress < ActiveRecord::Migration[8.1]
  def change
    change_table :workspace_memberships, bulk: true do |table|
      table.string :onboarding_version
      table.datetime :onboarding_completed_at
      table.datetime :onboarding_dismissed_at
    end

    change_table :operation_runs, bulk: true do |table|
      table.integer :progress_current, null: false, default: 0
      table.integer :progress_total
      table.string :progress_label
      table.boolean :retryable, null: false, default: false
      table.datetime :last_heartbeat_at
    end

    add_check_constraint :operation_runs,
      "progress_current >= 0 AND (progress_total IS NULL OR (progress_total >= 0 AND progress_current <= progress_total))",
      name: "operations_progress_valid"
  end
end
