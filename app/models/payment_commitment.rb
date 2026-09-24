class PaymentCommitment < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :expense_entry, optional: true
  belongs_to :account
  belongs_to :destination_account, class_name: "Account", optional: true
  belongs_to :excluded_provider_balance, class_name: "ProviderBalance", optional: true
  belongs_to :included_provider_balance, class_name: "ProviderBalance", optional: true
  has_many :payment_settlements, dependent: :restrict_with_error
  validates :amount, numericality: { greater_than: 0 }
  validates :state, inclusion: { in: %w[reserved settled cancelled] }

  def outstanding_amount
    return 0.to_d unless state == "reserved"
    [ amount - payment_settlements.sum { |settlement| settlement.amount }, 0.to_d ].max
  end
end
