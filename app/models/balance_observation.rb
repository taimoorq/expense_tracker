class BalanceObservation < ApplicationRecord
  include CurrencyQualified

  enum :source_kind, {
    manual: "manual",
    institution_file: "institution_file",
    migration: "migration",
    adjustment: "adjustment"
  }, prefix: true
  enum :status, {
    trusted: "trusted",
    superseded: "superseded",
    disputed: "disputed"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :account
  belongs_to :actor_membership, class_name: "WorkspaceMembership", optional: true
  belongs_to :source_import_batch, class_name: "ImportBatch", optional: true
  belongs_to :source_import_row, class_name: "ImportRow", optional: true

  validates :observed_at, :effective_through_at, presence: true
  validate :effective_window_is_coherent
  validate :currency_matches_account

  scope :trusted, -> { where(status: "trusted") }
  scope :latest_effective_first, -> { order(effective_through_at: :desc, created_at: :desc) }

  private

  def effective_window_is_coherent
    return if observed_at.blank? || effective_through_at.blank? || observed_at >= effective_through_at

    errors.add(:effective_through_at, "cannot be after the observation time")
  end

  def currency_matches_account
    return if account.blank? || account.currency_code.blank? || currency_code == account.currency_code

    errors.add(:currency_code, "must match the account currency")
  end
end
