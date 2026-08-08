class CreditCardPaymentPolicy < ApplicationRecord
  self.primary_key = :planning_template_id

  enum :estimate_policy, {
    minimum: "minimum",
    statement_balance: "statement_balance",
    available_cash: "available_cash",
    fixed_amount: "fixed_amount"
  }, prefix: true

  belongs_to :planning_template
  belongs_to :budget_workspace
  belongs_to :liability_account, class_name: "Account"
  belongs_to :payment_account, class_name: "Account"

  validates :minimum_payment, numericality: { greater_than_or_equal_to: 0 }
  validates :due_day, inclusion: { in: 1..31 }
  validates :priority, numericality: { only_integer: true, greater_than: 0 }
  validate :accounts_are_distinct

  private

  def accounts_are_distinct
    return unless liability_account_id == payment_account_id

    errors.add(:payment_account, "must differ from the liability account")
  end
end
