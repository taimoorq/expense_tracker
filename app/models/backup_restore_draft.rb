class BackupRestoreDraft < ApplicationRecord
  enum :state, {
    previewed: "previewed",
    queued: "queued",
    consumed: "consumed",
    failed: "failed",
    expired: "expired"
  }, prefix: true

  belongs_to :user
  belongs_to :budget_workspace
  belongs_to :operation_run, optional: true
  belongs_to :data_transfer_run, optional: true
  belongs_to :restore_checkpoint, optional: true

  validates :token_digest, format: { with: /\A[0-9a-f]{64}\z/ }, uniqueness: true
  validates :payload_checksum, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :payload_format_version, :expires_at, presence: true
  validate :payload_matches_state
  validate :expiration_is_after_creation
  validate :terminal_timestamps_are_coherent
  validate :workspace_links_are_coherent

  def available?
    state_previewed? && expires_at.future?
  end

  def dispatchable?
    state_queued? || ((state_previewed? || state_failed?) && expires_at.future?)
  end

  def payload
    Platform::Backup::RestoreDraftCodec.decode(encrypted_payload)
  end

  def preview_data
    { payload: payload, scopes: selected_scopes, encrypted: source_encrypted? }
  end

  def operation_request
    {
      payload_checksum: payload_checksum,
      scopes: selected_scopes,
      replacement: replacement_requested?
    }
  end

  def redacted_operation_parameters
    {
      "format_version" => payload_format_version,
      "scopes" => selected_scopes,
      "replacement" => replacement_requested?
    }
  end

  def queue!(operation_run:, data_transfer_run:, replacement_requested:)
    update!(
      operation_run: operation_run,
      data_transfer_run: data_transfer_run,
      replacement_requested: replacement_requested,
      state: "queued",
      failed_at: nil
    )
  end

  def consume!
    update!(state: "consumed", consumed_at: Time.current, encrypted_payload: "")
  end

  def fail!
    update!(state: "failed", failed_at: Time.current)
  end

  def expire!
    update!(state: "expired", failed_at: nil, expired_at: Time.current, encrypted_payload: "")
  end

  private

  def payload_matches_state
    payload_required = state_previewed? || state_queued? || state_failed?
    return if payload_required == encrypted_payload.present?

    errors.add(:encrypted_payload, payload_required ? "must be retained until completion" : "must be cleared after completion")
  end

  def expiration_is_after_creation
    return if expires_at.blank? || created_at.blank? || expires_at > created_at

    errors.add(:expires_at, "must be after creation")
  end

  def terminal_timestamps_are_coherent
    {
      consumed_at: state_consumed?,
      failed_at: state_failed?,
      expired_at: state_expired?
    }.each do |attribute, should_be_present|
      present = public_send(attribute).present?
      next if should_be_present == present

      errors.add(attribute, should_be_present ? "is required for this state" : "must be blank for this state")
    end
  end

  def workspace_links_are_coherent
    [ operation_run, data_transfer_run, restore_checkpoint ].compact.each do |record|
      next if record.budget_workspace_id == budget_workspace_id

      errors.add(record.class.model_name.singular.to_sym, "must belong to the same workspace")
    end
  end
end
