class PaymentPlan < ApplicationRecord
  belongs_to :user

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

  def matches_entry?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)
    return false unless entry.occurred_on == due_date_for_month(month_on)

    entry.source_file == "payment_plan" || entry.debt?
  end

  def apply_payment!(amount)
    return if amount.to_d <= 0

    update!(amount_paid: amount_paid + amount)
    update!(active: false) if remaining_balance <= 0
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
  end
end
