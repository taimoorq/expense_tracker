module AccountPageSetup
  extend ActiveSupport::Concern

  INDEX_PAGE_ATTRIBUTES = %i[
    accounts account_balance_rows net_worth_accounts assets_total liabilities_total net_worth_total
    latest_snapshot latest_balance_source accounts_with_balance_sources_count accounts_missing_balance_sources_count
    accounts_with_snapshots_count accounts_missing_snapshots_count trend_labels trend_values trend_rows calculation_version
  ].freeze
  DETAIL_PAGE_ATTRIBUTES = %i[
    balance_history_rows credit_card_progress connected_templates connected_templates_count
    activity_insights import_history movement_timeline reconciliation_bridge recent_activity
  ].freeze

  private

  def load_accounts_index_page
    page_data = Accounts::Summary.new(user: current_user, include_trend: true).call
    assign_accounts_index_data(page_data)
    @account = current_user.accounts.new
  end

  def load_account_detail_page
    @account ||= current_user.accounts.includes(:account_snapshots).find(params[:id])
    @account_snapshot = AccountSnapshot.new(account: @account, recorded_on: Date.current)
    @account_view = normalized_account_view
    @selected_range = normalized_account_range
    assign_account_detail_data(account_detail_page_data)
    @activity_ledger = account_activity_ledger if @account_view == "activity"
  end

  def account_detail_page_data
    Accounts::DetailPage.new(
      account: @account,
      range: @selected_range,
      view: @account_view
    ).call
  end

  def account_activity_ledger
    Accounts::ActivityLedgerQuery.new(
      account: @account,
      filters: activity_ledger_filters,
      preload_ledger_associations: true
    ).call
  end

  def activity_ledger_filters
    params.permit(:source, :direction, :starts_on, :ends_on, :merchant, :classification)
  end

  def normalized_account_view
    params[:view].to_s.presence_in(Accounts::DetailPage::DETAIL_VIEWS) || "overview"
  end

  def normalized_account_range
    params[:range].to_s.presence_in(Accounts::MovementTimeline::RANGE_OPTIONS.keys) || Accounts::MovementTimeline::DEFAULT_RANGE
  end

  def assign_accounts_index_data(page_data)
    INDEX_PAGE_ATTRIBUTES.each { |name| instance_variable_set("@#{name}", page_data.fetch(name)) }
  end

  def assign_account_detail_data(page_data)
    @balance_summary = page_data.fetch(:balance_summary)
    @account_story = page_data.fetch(:account_story)
    @calculation_version = page_data.fetch(:calculation_version)
    DETAIL_PAGE_ATTRIBUTES.each { |name| instance_variable_set("@#{name}", page_data[name]) }
  end
end
