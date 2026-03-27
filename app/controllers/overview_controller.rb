class OverviewController < ApplicationController
  def show
    Overview::PageData.new(user: current_user).call.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end
end
