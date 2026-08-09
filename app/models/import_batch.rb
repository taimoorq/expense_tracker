class ImportBatch < ApplicationRecord
  STATUSES_BY_COMPLETION_TIMESTAMP = {
    committed_at: %w[committed reverting reverted],
    failed_at: %w[failed],
    reverted_at: %w[reverted]
  }.freeze

  enum :import_kind, {
    account_activity: "account_activity",
    budget_plan: "budget_plan",
    backup_restore: "backup_restore"
  }, prefix: true
  enum :status, {
    previewed: "previewed",
    committing: "committing",
    committed: "committed",
    failed: "failed",
    reverting: "reverting",
    reverted: "reverted"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :account, optional: true
  belongs_to :import_profile, optional: true
  belongs_to :operation_run, optional: true
  belongs_to :actor_membership, class_name: "WorkspaceMembership", optional: true
  has_many :import_rows, dependent: :restrict_with_error
  has_many :balance_observations, foreign_key: :source_import_batch_id, dependent: :restrict_with_error

  validates :original_filename, :idempotency_key, :parser_version, :mapping_version, :fingerprint_version, presence: true
  validates :file_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :idempotency_key, uniqueness: { scope: %i[budget_workspace_id import_kind] }
  validates :row_count, :imported_count, :duplicate_count, :error_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :counts_are_coherent
  validate :coverage_window_is_coherent
  validate :terminal_state_is_coherent

  private

  def counts_are_coherent
    return if [ row_count, imported_count, duplicate_count, error_count ].any?(&:nil?)
    return if imported_count + duplicate_count + error_count <= row_count

    errors.add(:row_count, "must cover imported, duplicate, and error rows")
  end

  def coverage_window_is_coherent
    return if coverage_starts_on.blank? || coverage_ends_on.blank? || coverage_ends_on >= coverage_starts_on

    errors.add(:coverage_ends_on, "must be on or after coverage starts on")
  end

  def terminal_state_is_coherent
    STATUSES_BY_COMPLETION_TIMESTAMP.each do |timestamp_attribute, applicable_statuses|
      should_be_present = status.in?(applicable_statuses)
      is_present = public_send(timestamp_attribute).present?
      next if should_be_present == is_present

      errors.add(
        timestamp_attribute,
        should_be_present ? "is required when #{status}" : "must be blank before #{applicable_statuses.first}"
      )
    end
  end
end
