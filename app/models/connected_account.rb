class ConnectedAccount < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :bank_connection
  belongs_to :account, optional: true
  has_many :provider_balances, dependent: :restrict_with_error
  has_many :provider_transactions, dependent: :restrict_with_error
  validates :provider_connection_id, :provider_account_id, :name, :currency, presence: true
  validates :sign_multiplier, inclusion: { in: [ -1, 1 ] }
  validates :account_id, uniqueness: true, allow_nil: true
  validate :local_account_scope

  def latest_balance
    provider_balances.where.not(state: "disputed").order(reported_at: :desc, created_at: :desc).first
  end

  def supported_currency?
    currency == budget_workspace.default_currency_code
  end

  private

  def local_account_scope
    return if account.blank?
    errors.add(:account, "must belong to this workspace and use the same currency") unless account.budget_workspace_id == budget_workspace_id && account.currency_code == currency
  end
end
