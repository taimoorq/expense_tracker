class ImportRow < ApplicationRecord
  enum :normalization_result, {
    normalized: "normalized",
    duplicate: "duplicate",
    invalid: "invalid",
    unsupported: "unsupported"
  }, prefix: true
  enum :status, {
    accepted: "accepted",
    duplicate: "duplicate",
    rejected: "rejected",
    reversed: "reversed"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :import_batch
  belongs_to :financial_transaction, optional: true

  validates :row_number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :import_batch_id }
  validates :fingerprint, :fingerprint_version, presence: true
  validate :rejection_is_coherent

  private

  def rejection_is_coherent
    return unless status_rejected? && error_code.blank?

    errors.add(:error_code, "is required for rejected rows")
  end
end
