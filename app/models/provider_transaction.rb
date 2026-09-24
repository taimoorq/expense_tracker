class ProviderTransaction < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :connected_account
  belongs_to :financial_transaction, optional: true
  belongs_to :expense_entry, optional: true
  validates :provider_id, :content_digest, :currency, :description, presence: true
  validates :amount, numericality: { other_than: 0 }
  validates :posted_at, presence: true, unless: :pending?
  validates :state, inclusion: { in: %w[review accepted ignored changed] }

  def effective_at
    transacted_at || posted_at
  end

  def signed_amount
    # Provider movement signs describe deposits/withdrawals independently of a
    # bank's presentation convention for debt balances.
    amount
  end
end
