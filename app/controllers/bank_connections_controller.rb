class BankConnectionsController < ApplicationController
  before_action :load_workspace
  before_action :load_connection, except: %i[index new create timezone]
  rescue_from BankConnections::Simplefin::Client::Error, BankConnections::RefreshDispatch::Unavailable, ArgumentError, ActiveRecord::RecordInvalid, with: :show_error

  def index
    @connections = @workspace.bank_connections.order(:created_at)
  end

  def new
  end

  def create
    @workspace.update!(time_zone: params[:time_zone]) if params[:time_zone].present?
    @connection = BankConnections::Connect.call(workspace: @workspace, membership: @membership, setup_token: params.require(:setup_token))
    redirect_to bank_connection_path(@connection), notice: "SimpleFIN connected. Checking available accounts…", status: :see_other
  end

  def show
    @mappings = @connection.connected_accounts.includes(:account).order(:institution_name, :name).to_a
    @balances = ProviderBalance.where(connected_account_id: @mappings.map(&:id)).where.not(state: "disputed")
      .select("DISTINCT ON (connected_account_id) provider_balances.*").order(:connected_account_id, reported_at: :desc, created_at: :desc).index_by(&:connected_account_id)
    @accounts = @workspace.accounts.where(user_id: current_user.id).order(:name)
    @refresh = @connection.bank_refreshes.order(created_at: :desc).first
    @transactions = @workspace.provider_transactions.where(connected_account_id: @mappings.map(&:id), state: %w[review changed]).includes(:connected_account).order(fetched_at: :desc).limit(100)
    @accepted_transactions = @workspace.provider_transactions.where(connected_account_id: @mappings.map(&:id)).where.not(financial_transaction_id: nil).includes(:connected_account).order(fetched_at: :desc).limit(50)
    @transfer_candidates = @workspace.provider_transactions.where(pending: false).where.not(posted_at: nil).includes(:connected_account).order(fetched_at: :desc).limit(300)
    @entries = current_user.expense_entries.where(occurred_on: 90.days.ago.to_date..Date.current.end_of_month).order(occurred_on: :desc).limit(300)
  end

  def refresh
    BankConnections::RefreshDispatch.call(connection: @connection, membership: @membership)
    redirect_to @connection, notice: "Refresh queued. You can leave this page while it runs.", status: :see_other
  end

  def update
    raise ArgumentError, "Reconnect before scheduling automatic refreshes." unless @connection.connected?
    @connection.update!(automatic_refresh: ActiveModel::Type::Boolean.new.cast(params[:automatic_refresh]), next_refresh_at: Time.current)
    redirect_to @connection, notice: "Refresh schedule updated.", status: :see_other
  end

  def reconnect
    BankConnections::Connect.call(workspace: @workspace, membership: @membership, setup_token: params.require(:setup_token), connection: @connection)
    redirect_to @connection, notice: "Reconnected. Existing account identities will be checked.", status: :see_other
  end

  def destroy
    BankConnections::Disconnect.call(connection: @connection, membership: @membership)
    redirect_to @connection, notice: "Disconnected. History was kept. You can also revoke this app in SimpleFIN.", status: :see_other
  end

  def map_account
    mapping = @connection.connected_accounts.find(params.require(:mapping_id))
    BankConnections::MapAccount.call(mapping: mapping, membership: @membership,
      account_id: params[:account_id], name: params[:name], kind: params[:kind], ignore: params[:choice] == "ignore",
      sign_multiplier: params[:sign_multiplier].presence || 1,
      import_transactions: ActiveModel::Type::Boolean.new.cast(params[:import_transactions]))
    redirect_to @connection, notice: "Account mapping saved. Review its balance below. Recent transactions will arrive on the next allowed refresh.", status: :see_other
  end

  def timezone
    @workspace.update!(time_zone: params.require(:time_zone))
    redirect_to bank_connections_path, notice: "Timezone saved. Existing explicit transaction times retain their original timezone.", status: :see_other
  end

  private

  def load_workspace
    context = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    @workspace, @membership = context.workspace, context.membership
    BankConnections::Access.authorize!(workspace: @workspace, membership: @membership)
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end

  def load_connection
    @connection = @workspace.bank_connections.find(params[:id])
  end

  def show_error(error)
    # Never echo the submitted token, even on an invalid form.
    redirect_to(@connection&.persisted? ? bank_connection_path(@connection) : new_bank_connection_path,
      alert: error.message, status: :see_other)
  end
end
