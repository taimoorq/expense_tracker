class MonthlyBill < ApplicationRecord
  enum :kind, {
    fixed_payment: 0,
    variable_bill: 1
  }

  validates :name, presence: true
  validates :due_day, inclusion: { in: 1..31 }

  scope :active_only, -> { where(active: true).order(:due_day, :name) }

  def due_date_for_month(month_on)
    Date.new(month_on.year, month_on.month, [ due_day, month_on.end_of_month.day ].min)
  end
end
