class MonthClose < ApplicationRecord
  enum :state, { closed: "closed", superseded: "superseded" }, prefix: true

  belongs_to :budget_workspace
  belongs_to :budget_period
  belongs_to :closed_by_membership, class_name: "WorkspaceMembership", optional: true
  belongs_to :reopens_month_close, class_name: "MonthClose", optional: true
  belongs_to :close_operation, class_name: "OperationRun", optional: true
  has_many :item_snapshots, class_name: "MonthCloseItemSnapshot", dependent: :restrict_with_error
  has_many :transaction_snapshots, class_name: "MonthCloseTransactionSnapshot", dependent: :restrict_with_error

  validates :calculation_version, :closed_at, presence: true
  validates :calculation_input_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :unresolved_count, :unmatched_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def report_summary
    Budgeting::PeriodSummary::Result.new(
      planned_income: planned_income,
      planned_outflow: planned_outflow,
      planned_net: planned_net,
      actual_income: actual_income,
      actual_outflow: actual_outflow,
      actual_net: actual_net,
      remaining_income: remaining_income,
      remaining_outflow: remaining_outflow,
      forecast_income: forecast_income,
      forecast_outflow: forecast_outflow,
      forecast_net: forecast_net,
      income_variance: income_variance,
      outflow_variance: outflow_variance,
      unmatched_count: unmatched_count
    )
  end
end
