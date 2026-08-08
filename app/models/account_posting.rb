class AccountPosting < ApplicationRecord
  include CurrencyQualified

  enum :role, {
    primary: "primary",
    source: "source",
    destination: "destination",
    adjustment: "adjustment"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :financial_transaction
  belongs_to :account

  validates :amount, numericality: { other_than: 0 }
  validates :sequence_number,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :financial_transaction_id }
  validate :currency_matches_transaction_and_account

  private

  def currency_matches_transaction_and_account
    if financial_transaction.present? && currency_code != financial_transaction.currency_code
      errors.add(:currency_code, "must match the transaction currency")
    end
    if account.present? && account.currency_code.present? && currency_code != account.currency_code
      errors.add(:currency_code, "must match the account currency")
    end
  end
end
