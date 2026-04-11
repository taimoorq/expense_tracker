class OverviewController < ApplicationController
  def show
    @overview = Overview::Presenter.new(
      user: current_user,
      account_flow_month_window: params[:account_flow_months]
    )

    render partial: "overview/account_flow_panel", formats: [ :html ], locals: { overview: @overview } if request.headers["Turbo-Frame"] == "overview_account_flow"
  end
end
