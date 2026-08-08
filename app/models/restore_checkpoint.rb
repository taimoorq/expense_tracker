class RestoreCheckpoint < ApplicationRecord
  enum :state, { ready: "ready", restored: "restored", expired: "expired" }, prefix: true

  belongs_to :budget_workspace
  belongs_to :actor_membership, class_name: "WorkspaceMembership", optional: true
  belongs_to :checkpoint_operation, class_name: "OperationRun", optional: true

  validates :payload_format_version, :encryption_version, :expires_at, presence: true
  validates :payload_checksum, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :encrypted_payload, presence: true
  validate :restored_state_is_coherent

  scope :available, -> { state_ready.where(expires_at: Time.current..) }

  def available?
    state_ready? && expires_at.future?
  end

  private

  def restored_state_is_coherent
    return if state_restored? == restored_at.present?

    errors.add(:restored_at, state_restored? ? "is required after rollback" : "must be blank until rollback")
  end
end
