module Identity
  # Only the signup transaction calls this. Existing users keep the audited
  # migration workflow, including users whose old workspace is still empty.
  class NewWorkspaceSetup
    def self.call(user:)
      user.with_lock do
        legacy_models = Platform::TargetBackfill::WorkspaceBootstrap::LEGACY_TABLES
        if BudgetWorkspace.exists?(legacy_owner_user: user) || user.accounts.exists? ||
            legacy_models.any? { |model| model.where(user_id: user.id).exists? }
          raise ArgumentError, "Existing financial workspaces must use the workspace upgrade process."
        end

        result = Platform::TargetBackfill::Runner.call(user: user)
        raise ArgumentError, "The new workspace could not be verified." unless result.success?

        result.workspace.update!(target_reads_enabled: true, target_writes_enabled: true)
        result.workspace
      end
    end
  end
end
