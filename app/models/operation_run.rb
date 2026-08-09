class OperationRun < ApplicationRecord
  enum :state, {
    pending: "pending",
    running: "running",
    succeeded: "succeeded",
    failed: "failed",
    reversed: "reversed"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :actor_membership, class_name: "WorkspaceMembership", optional: true
  has_many :audit_events, dependent: :restrict_with_error
  has_many :restore_checkpoints, foreign_key: :checkpoint_operation_id, dependent: :restrict_with_error
  has_one :account_activity_import_draft, dependent: :restrict_with_error
  has_one :backup_restore_draft, dependent: :restrict_with_error
  has_one :backup_export_artifact, dependent: :restrict_with_error

  validates :operation_type, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: { scope: %i[budget_workspace_id operation_type] }
  validates :request_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :progress_current, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :progress_total, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :job_arguments, length: { maximum: 10 }
  validate :completion_state_is_coherent
  validate :job_metadata_is_coherent
  validate :progress_is_bounded

  scope :open, -> { where(state: %w[pending running]) }

  def progress_percent
    return 100 if state_succeeded?
    return if progress_total.blank? || progress_total.zero?

    ((progress_current.to_d / progress_total) * 100).floor.clamp(0, 100)
  end

  def record_progress!(current:, total: progress_total, label: progress_label)
    update!(
      progress_current: current,
      progress_total: total,
      progress_label: label,
      last_heartbeat_at: Time.current
    )
  end

  def dispatched?
    job_class.present?
  end

  private

  def completion_state_is_coherent
    terminal = state_succeeded? || state_failed? || state_reversed?
    return if terminal == completed_at.present?

    errors.add(:completed_at, terminal ? "is required when complete" : "must be blank before completion")
  end

  def progress_is_bounded
    return if progress_total.blank? || progress_current <= progress_total

    errors.add(:progress_current, "cannot exceed the progress total")
  end

  def job_metadata_is_coherent
    errors.add(:job_arguments, "must be an array") unless job_arguments.is_a?(Array)
    return if job_class.present? || job_arguments.empty?

    errors.add(:job_class, "is required when job arguments are present")
  end
end
