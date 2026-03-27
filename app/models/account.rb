class Account < ApplicationRecord
  belongs_to :user
  has_many :account_snapshots, -> { order(recorded_on: :desc, created_at: :desc) }, dependent: :destroy
  encrypts :teller_access_token

  enum :kind, {
    checking: 0,
    savings: 1,
    brokerage: 2,
    retirement: 3,
    credit_card: 4,
    loan: 5,
    cash: 6,
    other_asset: 7,
    other_liability: 8
  }

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :kind, presence: true
  validate :teller_fields_are_consistent

  scope :active_first, -> { order(active: :desc, name: :asc) }
  scope :assets, -> { where(kind: [ :checking, :savings, :brokerage, :retirement, :cash, :other_asset ]) }
  scope :liabilities, -> { where(kind: [ :credit_card, :loan, :other_liability ]) }

  def latest_snapshot
    account_snapshots.select(&:persisted?).max_by { |snapshot| [ snapshot.recorded_on, snapshot.created_at ] }
  end

  def latest_balance
    latest_snapshot&.balance
  end

  def current_balance(as_of: Date.current)
    base_balance = latest_balance.to_d
    base_balance + posted_entries_delta(as_of: as_of)
  end

  def asset?
    checking? || savings? || brokerage? || retirement? || cash? || other_asset?
  end

  def liability?
    credit_card? || loan? || other_liability?
  end

  def display_balance
    current_balance
  end

  def posted_entries_delta(as_of: Date.current)
    scope = user.expense_entries
                .where(source_account_id: id, status: ExpenseEntry.statuses[:paid])
                .where.not(occurred_on: nil)
                .where(occurred_on: ..as_of)

    if latest_snapshot.present?
      scope = scope.where("occurred_on > ?", latest_snapshot.recorded_on)
    end

    scope.to_a.sum { |entry| entry.income? ? entry.effective_amount.to_d : -entry.effective_amount.to_d }
  end

  def teller_connected?
    teller_sync_enabled? && teller_account_id.present? && teller_access_token.present?
  end

  private

  def teller_fields_are_consistent
    return unless teller_related_fields_present?

    if teller_account_id.blank?
      errors.add(:teller_account_id, "must be present when Teller sync is enabled")
    end

    if teller_access_token.blank?
      errors.add(:teller_access_token, "must be present when Teller sync is enabled")
    end
  end

  def teller_related_fields_present?
    teller_sync_enabled? || teller_account_id.present? || teller_enrollment_id.present? || teller_access_token.present?
  end
end
