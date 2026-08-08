module LegacyWorkspaceOwned
  extend ActiveSupport::Concern

  included do
    before_validation :assign_legacy_workspace
    validate :legacy_workspace_matches_user
  end

  private

  def assign_legacy_workspace
    self.budget_workspace ||= BudgetWorkspace.find_by(legacy_owner_user_id: user_id) if user_id.present?
  end

  def legacy_workspace_matches_user
    return if budget_workspace.blank? || user_id.blank?
    return if budget_workspace.legacy_owner_user_id == user_id
    return if budget_workspace.workspace_memberships.status_active.where(user_id: user_id).exists?

    errors.add(:budget_workspace, "must include the user as an active member")
  end
end
