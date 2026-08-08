class ReportsController < ApplicationController
  def index
    @report = Reports::OverviewQuery.call(user: current_user)
  end

  def sources
    @sources = Reports::SourceDrilldown.call(
      user: current_user,
      category: params[:category],
      starts_on: params[:starts_on],
      ends_on: params[:ends_on]
    )
  rescue ArgumentError => error
    redirect_to reports_path, alert: error.message
  end
end
