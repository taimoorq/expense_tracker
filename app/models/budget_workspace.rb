class BudgetWorkspace < ApplicationRecord
  enum :status, {
    active: "active",
    suspended: "suspended",
    closing: "closing",
    closed: "closed"
  }, prefix: true

  has_many :workspace_memberships, dependent: :restrict_with_error
  has_many :users, through: :workspace_memberships
  has_many :accounts, dependent: :restrict_with_error
  has_many :budget_periods, dependent: :restrict_with_error
  has_many :categories, dependent: :restrict_with_error
  has_many :planning_templates, dependent: :restrict_with_error
  has_many :recurring_occurrences, dependent: :restrict_with_error
  has_many :budget_items, dependent: :restrict_with_error
  has_many :month_closes, dependent: :restrict_with_error
  has_many :month_close_item_snapshots, dependent: :restrict_with_error
  has_many :month_close_transaction_snapshots, dependent: :restrict_with_error
  has_many :financial_transactions, dependent: :restrict_with_error
  has_many :account_postings, dependent: :restrict_with_error
  has_many :budget_allocations, dependent: :restrict_with_error
  has_many :balance_observations, dependent: :restrict_with_error
  has_many :import_profiles, dependent: :restrict_with_error
  has_many :import_batches, dependent: :restrict_with_error
  has_many :import_rows, dependent: :restrict_with_error
  has_many :operation_runs, dependent: :restrict_with_error
  has_many :audit_events, dependent: :restrict_with_error
  has_many :data_transfer_runs, dependent: :restrict_with_error
  has_many :restore_checkpoints, dependent: :restrict_with_error
  has_many :backup_restore_drafts, dependent: :restrict_with_error
  has_many :backup_export_artifacts, dependent: :restrict_with_error
  has_many :legacy_record_mappings, dependent: :restrict_with_error
  has_many :migration_discrepancies, dependent: :restrict_with_error
  belongs_to :legacy_owner_user, class_name: "User", optional: true

  validates :name, presence: true
  validates :default_currency_code, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validate :closed_state_is_coherent
  validate :target_flags_are_coherent

  private

  def closed_state_is_coherent
    return if status_closed? == closed_at.present?

    errors.add(:closed_at, status_closed? ? "is required when closed" : "must be blank unless closed")
  end

  def target_flags_are_coherent
    return unless target_reads_enabled? && !target_writes_enabled?

    errors.add(:target_reads_enabled, "requires target writes")
  end
end
