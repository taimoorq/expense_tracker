module BankConnections
  class RefreshJob < ApplicationJob
    queue_as :imports
    limits_concurrency key: ->(operation_id) { BankRefresh.find_by(operation_run_id: operation_id)&.bank_connection_id || operation_id }, to: 1, duration: 5.minutes
    discard_on ActiveRecord::RecordNotFound
    retry_on Simplefin::Client::Error, wait: :polynomially_longer, attempts: 3

    def perform(operation_id)
      refresh = BankRefresh.find_by!(operation_run_id: operation_id)
      Refresh.new(refresh: refresh).call
    end
  end
end
