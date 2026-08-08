class DataTransferRun < ApplicationRecord
  enum :operation, { export: "export", preview: "preview", restore: "restore" }, prefix: true
  enum :state, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :actor_membership, class_name: "WorkspaceMembership", optional: true
  belongs_to :operation_run, optional: true

  validates :payload_format_version, presence: true
  validates :payload_checksum, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :completion_state_is_coherent

  private

  def completion_state_is_coherent
    terminal = state_succeeded? || state_failed?
    return if terminal == completed_at.present?

    errors.add(:completed_at, terminal ? "is required when complete" : "must be blank before completion")
  end
end
