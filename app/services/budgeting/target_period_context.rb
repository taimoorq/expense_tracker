module Budgeting
  class TargetPeriodContext
    Result = Data.define(:workspace, :membership, :period)

    def self.call(user:, budget_month:)
      workspace = BudgetWorkspace.find_by(legacy_owner_user_id: user.id)
      return if workspace.blank? || !workspace.target_reads_enabled?

      membership = workspace.workspace_memberships.status_active.find_by(user: user)
      return if membership.blank?

      mapping = workspace.legacy_record_mappings.find_by(
        legacy_record_type: "BudgetMonth",
        legacy_record_id: budget_month.id,
        target_record_type: "BudgetPeriod"
      )
      period = workspace.budget_periods.find_by(id: mapping&.target_record_id)
      return if period.blank?

      Result.new(workspace: workspace, membership: membership, period: period)
    end
  end
end
