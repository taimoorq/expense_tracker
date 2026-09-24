class AddWorkflowOnboardingPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_memberships, :onboarding_path, :string
    add_column :workspace_memberships, :onboarding_recurring_skipped_at, :datetime
    add_column :workspace_memberships, :onboarding_balance_deferred_at, :datetime
    add_column :workspace_memberships, :onboarding_reviewed_at, :datetime
    add_check_constraint :workspace_memberships,
      "onboarding_path IS NULL OR onboarding_path IN ('simplefin', 'manual', 'import')",
      name: "membership_onboarding_path_valid"
  end
end
