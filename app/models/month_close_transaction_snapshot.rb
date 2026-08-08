class MonthCloseTransactionSnapshot < ApplicationRecord
  include CurrencyQualified

  enum :flow_kind, {
    income: "income",
    outflow: "outflow",
    transfer: "transfer",
    adjustment: "adjustment"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :month_close
  belongs_to :financial_transaction

  validates :description_snapshot, :effective_on, presence: true
  validates :gross_amount, :allocated_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :financial_transaction_id, uniqueness: { scope: :month_close_id }
  validate :allocation_does_not_exceed_transaction

  private

  def allocation_does_not_exceed_transaction
    return if gross_amount.blank? || allocated_amount.blank? || allocated_amount <= gross_amount

    errors.add(:allocated_amount, "cannot exceed the transaction amount")
  end
end
