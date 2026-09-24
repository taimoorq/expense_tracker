class AccountSnapshot < ApplicationRecord
  belongs_to :account

  delegate :user, to: :account

  # Form inputs only. Storage, imports and target observations continue using
  # the existing end-of-day cutoff, including for an opening balance.
  attr_writer :balance_date, :balance_timing

  before_validation :apply_balance_date

  validates :recorded_on, presence: true, uniqueness: { scope: :account_id }
  validates :balance, presence: true
  validates :balance, numericality: true, allow_nil: true
  validates :available_balance, numericality: true, allow_nil: true
  validates :balance_timing, inclusion: { in: %w[opening closing] }

  def balance_date
    defined?(@balance_date) ? @balance_date : recorded_on
  end

  def balance_timing
    @balance_timing || "closing"
  end

  private

  def apply_balance_date
    return unless defined?(@balance_date)

    date = ActiveModel::Type::Date.new.cast(@balance_date)
    self.recorded_on = balance_timing == "opening" ? date&.prev_day : date
  end
end
