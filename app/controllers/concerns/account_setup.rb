module AccountSetup
  extend ActiveSupport::Concern

  private

  def default_account_attributes
    { include_in_net_worth: true }
  end

  def build_initial_snapshot(account)
    return nil unless initial_snapshot_requested?

    account.account_snapshots.new(initial_snapshot_params)
  end

  def initial_snapshot_requested?
    snapshot_params = initial_snapshot_params.to_h

    snapshot_params["balance"].present? || snapshot_params["available_balance"].present? || snapshot_params["notes"].present?
  end

  def initial_snapshot_params
    account_scope = params.fetch(:account, ActionController::Parameters.new)
    snapshot_scope = account_scope[:initial_snapshot] || ActionController::Parameters.new

    if snapshot_scope.respond_to?(:permit)
      snapshot_scope.permit(:recorded_on, :balance, :available_balance, :notes)
    else
      ActionController::Parameters.new(snapshot_scope).permit(:recorded_on, :balance, :available_balance, :notes)
    end
  end
end
