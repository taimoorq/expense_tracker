class PaymentSettlement < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :payment_commitment
  belongs_to :financial_transaction
  validates :amount, numericality: { greater_than: 0 }
end
