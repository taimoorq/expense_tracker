class OverviewController < ApplicationController
  def show
    @overview = Overview::Presenter.new(user: current_user)
  end
end
