class MonthCloseItemSnapshot < ApplicationRecord
  include CurrencyQualified

  enum :flow_kind, { income: "income", outflow: "outflow", transfer: "transfer" }, prefix: true

  belongs_to :budget_workspace
  belongs_to :month_close
  belongs_to :budget_item

  validates :planned_amount, :actual_amount, :remaining_amount,
    numericality: { greater_than_or_equal_to: 0 }
  validates :budget_item_id, uniqueness: { scope: :month_close_id }
end
