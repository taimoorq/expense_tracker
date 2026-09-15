class BackupArchive < ApplicationRecord
  enum :trigger, { manual: "manual", scheduled: "scheduled" }, prefix: true
  enum :state, {
    pending: "pending",
    writing: "writing",
    ready: "ready",
    failed: "failed",
    deleting: "deleting",
    deleted: "deleted"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :backup_schedule, optional: true
  belongs_to :actor_membership, class_name: "WorkspaceMembership"
  belongs_to :operation_run
  belongs_to :data_transfer_run

  validates :storage_adapter, :storage_key, :filename, :payload_format_version,
    :envelope_version, :encryption_key_id, presence: true
  validates :payload_checksum, :archive_checksum,
    format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :workspace_links_are_coherent
  validate :schedule_slot_is_coherent
  validate :state_is_coherent

  scope :available, -> { state_ready.order(created_at: :desc) }
  scope :active, -> { where(state: %w[pending writing]) }

  def operation_request
    {
      archive_id: id,
      trigger: trigger,
      scheduled_for: scheduled_for&.iso8601,
      storage_adapter: storage_adapter,
      storage_key: storage_key,
      scopes: data_transfer_run.selected_scopes,
      payload_format_version: payload_format_version,
      envelope_version: envelope_version,
      encryption_key_id: encryption_key_id
    }
  end

  def begin_writing!(payload_checksum:, archive_checksum:, byte_size:)
    update!(
      state: "writing",
      started_at: started_at || Time.current,
      payload_checksum: payload_checksum,
      archive_checksum: archive_checksum,
      byte_size: byte_size,
      error_code: nil
    )
  end

  def reset_unwritten!
    update!(
      state: "pending",
      payload_checksum: nil,
      archive_checksum: nil,
      byte_size: nil,
      stored_at: nil,
      verified_at: nil,
      failed_at: nil,
      error_code: nil
    )
  end

  def mark_ready!(payload_checksum:, archive_checksum:, byte_size:)
    update!(
      state: "ready",
      payload_checksum: payload_checksum,
      archive_checksum: archive_checksum,
      byte_size: byte_size,
      stored_at: stored_at || Time.current,
      verified_at: Time.current,
      failed_at: nil,
      error_code: nil
    )
  end

  def fail!(error_code:)
    update!(state: "failed", failed_at: Time.current, verified_at: nil, error_code: error_code)
  end

  def begin_deleting!
    update!(state: "deleting", verified_at: nil, deleting_at: Time.current, error_code: nil)
  end

  def mark_deleted!
    update!(state: "deleted", deleting_at: nil, deleted_at: Time.current, verified_at: nil, error_code: nil)
  end

  private

  def workspace_links_are_coherent
    [ backup_schedule, actor_membership, operation_run, data_transfer_run ].compact.each do |record|
      next if record.budget_workspace_id == budget_workspace_id

      errors.add(record.class.model_name.singular.to_sym, "must belong to the same workspace")
    end
  end

  def schedule_slot_is_coherent
    coherent = trigger_manual? ? backup_schedule.blank? && scheduled_for.blank? : backup_schedule.present? && scheduled_for.present?
    errors.add(:scheduled_for, "must match the archive trigger") unless coherent
  end

  def state_is_coherent
    {
      verified_at: state_ready?,
      failed_at: state_failed?,
      deleting_at: state_deleting?,
      deleted_at: state_deleted?
    }.each do |attribute, required|
      present = public_send(attribute).present?
      errors.add(attribute, required ? "is required for this state" : "must be blank for this state") unless required == present
    end

    return unless state_ready? || state_deleting? || state_deleted?
    return if stored_at.present? && payload_checksum.present? && archive_checksum.present? && byte_size.present?

    errors.add(:base, "stored metadata is required after an archive is ready")
  end
end
