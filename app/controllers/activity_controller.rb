class ActivityController < ApplicationController
  def index
    @activity = Activity::IndexQuery.call(
      user: current_user,
      view: params[:view],
      account_id: params[:account_id],
      starts_on: params[:starts_on],
      ends_on: params[:ends_on],
      direction: params[:direction],
      transaction_id: params[:transaction_id]
    )
  end
end
