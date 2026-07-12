class Account < ApplicationRecord
  belongs_to :user
  has_many :account_snapshots, -> { order(recorded_on: :desc, created_at: :desc) }, dependent: :destroy
  has_many :account_activity_imports, dependent: :destroy
  has_many :account_activities, dependent: :destroy

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

  scope :active_first, -> { order(active: :desc, name: :asc) }
  scope :assets, -> { where(kind: [ :checking, :savings, :brokerage, :retirement, :cash, :other_asset ]) }
  scope :liabilities, -> { where(kind: [ :credit_card, :loan, :other_liability ]) }

  def latest_snapshot
    account_snapshots.select(&:persisted?).max_by { |snapshot| [ snapshot.recorded_on, snapshot.created_at ] }
  end

  def latest_balance
    latest_snapshot&.balance
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

  def resolved_balance(as_of: Date.current)
    Accounts::BalanceResolver.new(account: self, as_of: as_of).call
  end

  def posted_entries_delta(as_of: Date.current)
    scope = user.expense_entries
                .where(status: ExpenseEntry.statuses[:paid])
                .where("source_account_id = :id OR destination_account_id = :id", id: id)
                .where.not(occurred_on: nil)
                .where(occurred_on: ..as_of)

    if latest_snapshot.present?
      scope = scope.where("occurred_on > ?", latest_snapshot.recorded_on)
    end

    scope.to_a.sum { |entry| account_delta_for(entry) }
  end

  def account_delta_for(entry)
    Accounts::EntryImpact.new(account: self, entry: entry).delta
  end

  def imported_card_balance_source(as_of: Date.current)
    return nil unless credit_card?

    balance = resolved_balance(as_of: as_of)
    return nil unless balance.balance_available
    return nil unless balance.balance_source.in?([ :institution_import, :imported_activity ])

    {
      type: balance.balance_source,
      label: balance.balance_source_label,
      record: balance.balance_source_record,
      recorded_on: balance.balance_source_recorded_on,
      base_balance: balance.base_balance,
      activity_delta: balance.paid_delta,
      current_balance: balance.current_balance,
      activity_through_on: balance.activity_through_on,
      activity_count: balance.paid_entries_count
    }
  end

  def current_balance(as_of: Date.current)
    resolved_balance(as_of: as_of).current_balance
  end
end
