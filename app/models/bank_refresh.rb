class BankRefresh < ApplicationRecord
  belongs_to :budget_workspace
  belongs_to :bank_connection
  belongs_to :operation_run
  validates :state, inclusion: { in: %w[pending running succeeded partial failed cancelled] }

  def terminal?
    state.in?(%w[succeeded partial failed cancelled])
  end
end
