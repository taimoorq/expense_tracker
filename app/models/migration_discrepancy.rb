class MigrationDiscrepancy < ApplicationRecord
  enum :status, { open: "open", resolved: "resolved", accepted: "accepted" }, prefix: true

  belongs_to :budget_workspace
  belongs_to :operation_run, optional: true

  validates :legacy_record_type, :legacy_record_id, :code, presence: true
  validates :code, uniqueness: { scope: %i[budget_workspace_id legacy_record_type legacy_record_id] }
  validate :resolution_state_is_coherent

  private

  def resolution_state_is_coherent
    return if status_open? == resolved_at.blank?

    errors.add(:resolved_at, status_open? ? "must be blank while open" : "is required when resolved")
  end
end
