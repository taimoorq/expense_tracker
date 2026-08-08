class WorkspaceMembership < ApplicationRecord
  enum :role, { owner: "owner", editor: "editor", viewer: "viewer" }, prefix: true
  enum :status, {
    invited: "invited",
    active: "active",
    suspended: "suspended",
    removed: "removed"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :user
  has_many :restore_checkpoints, foreign_key: :actor_membership_id, dependent: :restrict_with_error

  validates :user_id, uniqueness: { scope: :budget_workspace_id }
  validate :removed_state_is_coherent

  private

  def removed_state_is_coherent
    return if status_removed? == removed_at.present?

    errors.add(:removed_at, status_removed? ? "is required when removed" : "must be blank unless removed")
  end
end
