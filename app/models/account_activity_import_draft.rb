class AccountActivityImportDraft < ApplicationRecord
  enum :state, {
    previewed: "previewed",
    queued: "queued",
    consumed: "consumed",
    failed: "failed",
    expired: "expired"
  }, prefix: true

  belongs_to :user
  belongs_to :account
  belongs_to :budget_workspace
  belongs_to :operation_run, optional: true

  validates :token_digest, format: { with: /\A[0-9a-f]{64}\z/ }, uniqueness: true
  validates :commit_idempotency_key, presence: true
  validates :file_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :rows_count, :imported_count, :duplicate_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true
  validate :counts_are_bounded
  validate :payload_matches_state
  validate :ownership_is_coherent
  validate :expiration_is_after_creation
  validate :terminal_timestamps_are_coherent

  scope :awaiting_dispatch, -> {
    state_previewed.where("expires_at > ?", Time.current).or(state_queued)
  }

  def preview
    preview_payload.deep_symbolize_keys
  end

  def available?
    state_previewed? && expires_at.future?
  end

  def dispatchable?
    state_queued? || ((state_previewed? || state_failed?) && expires_at.future?)
  end

  def idempotency_key
    preview.fetch(:commit_idempotency_key)
  end

  def operation_request
    {
      account_id: account_id,
      file_digest: file_digest,
      rows_count: rows_count,
      imported_count: imported_count,
      duplicate_count: duplicate_count
    }
  end

  def redacted_operation_parameters
    operation_request.except(:file_digest)
  end

  def consume!
    update!(state: "consumed", consumed_at: Time.current, preview_payload: {})
  end

  def queue!(operation_run:)
    update!(
      operation_run: operation_run,
      state: "queued",
      failed_at: nil
    )
  end

  def fail!
    update!(state: "failed", failed_at: Time.current)
  end

  def expire!
    update!(state: "expired", failed_at: nil, expired_at: Time.current, preview_payload: {})
  end

  private

  def counts_are_bounded
    return unless rows_count && imported_count && duplicate_count
    return if imported_count + duplicate_count <= rows_count

    errors.add(:rows_count, "must cover imported and duplicate rows")
  end

  def payload_matches_state
    unless preview_payload.is_a?(Hash)
      errors.add(:preview_payload, "must be an object")
      return
    end

    if (state_previewed? || state_queued? || state_failed?) && preview_payload.empty?
      errors.add(:preview_payload, "must be present until the import is consumed or expires")
    elsif (state_consumed? || state_expired?) && preview_payload.present?
      errors.add(:preview_payload, "must be cleared after the import is consumed or expires")
    end
  end

  def ownership_is_coherent
    return if account.blank?

    errors.add(:account, "must belong to the same user") if account.user_id != user_id
    if account.budget_workspace_id != budget_workspace_id
      errors.add(:account, "must belong to the same workspace")
    end
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
      is_present = public_send(attribute).present?
      next if should_be_present == is_present

      errors.add(attribute, should_be_present ? "is required for this state" : "must be blank for this state")
    end
  end
end
