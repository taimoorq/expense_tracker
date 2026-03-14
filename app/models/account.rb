class Account < ApplicationRecord
  belongs_to :user
  has_many :account_snapshots, -> { order(recorded_on: :desc, created_at: :desc) }, dependent: :destroy

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
    latest_balance || 0
  end
end
