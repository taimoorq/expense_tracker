class PaymentPlan < ApplicationRecord
  validates :name, presence: true
  validates :total_due, presence: true
  validates :amount_paid, presence: true
  validates :due_day, inclusion: { in: 1..31 }

  scope :active_only, -> { where(active: true).order(:due_day, :name) }

  def remaining_balance
    [ total_due - amount_paid, 0 ].max
  end

  def monthly_amount
    target = monthly_target.presence || remaining_balance
    [ target, remaining_balance ].min
  end

  def due_date_for_month(month_on)
    Date.new(month_on.year, month_on.month, [ due_day, month_on.end_of_month.day ].min)
  end

  def apply_payment!(amount)
    return if amount.to_d <= 0

    update!(amount_paid: amount_paid + amount)
    update!(active: false) if remaining_balance <= 0
  end
end
