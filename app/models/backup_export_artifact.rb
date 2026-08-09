class BackupExportArtifact < ApplicationRecord
  RETENTION = 1.day

  enum :state, {
    pending: "pending",
    ready: "ready",
    failed: "failed",
    expired: "expired"
  }, prefix: true

  belongs_to :user
  belongs_to :budget_workspace
  belongs_to :operation_run
  belongs_to :data_transfer_run

  validates :generation_key, :content_type, :expires_at, presence: true
  validate :workspace_links_are_coherent
  validate :state_is_coherent

  scope :available, -> { state_ready.where(expires_at: Time.current..) }

  def available?
    state_ready? && expires_at.future?
  end

  def export_password
    return if encrypted_export_password.blank?

    Platform::Backup::RestoreDraftCodec.decode(encrypted_export_password).fetch(:password)
  end

  def contents
    raise ActiveRecord::RecordNotFound unless available?

    Platform::Backup::RestoreDraftCodec.decode(encrypted_contents).fetch(:contents)
  end

  def operation_request
    {
      generation_key: generation_key,
      scopes: data_transfer_run.selected_scopes
    }
  end

  def write!(contents:, filename:)
    update!(
      encrypted_contents: Platform::Backup::RestoreDraftCodec.encode(contents: contents),
      encrypted_export_password: nil,
      filename: filename,
      state: "ready",
      ready_at: Time.current
    )
  end

  def fail!
    update!(
      state: "failed",
      ready_at: nil,
      failed_at: Time.current,
      expired_at: nil,
      encrypted_contents: nil,
      encrypted_export_password: nil,
      filename: nil
    )
  end

  def expire!
    update!(
      state: "expired",
      expired_at: Time.current,
      ready_at: nil,
      failed_at: nil,
      encrypted_contents: nil,
      encrypted_export_password: nil
    )
  end

  private

  def workspace_links_are_coherent
    [ operation_run, data_transfer_run ].compact.each do |record|
      next if record.budget_workspace_id == budget_workspace_id

      errors.add(record.class.model_name.singular.to_sym, "must belong to the same workspace")
    end
  end

  def state_is_coherent
    {
      ready_at: state_ready?,
      failed_at: state_failed?,
      expired_at: state_expired?
    }.each do |attribute, should_be_present|
      present = public_send(attribute).present?
      errors.add(attribute, should_be_present ? "is required for this state" : "must be blank for this state") unless present == should_be_present
    end
    return unless state_ready? && (encrypted_contents.blank? || filename.blank?)

    errors.add(:encrypted_contents, "and filename are required when ready")
  end
end
