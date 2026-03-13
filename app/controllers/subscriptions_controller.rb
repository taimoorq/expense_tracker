class SubscriptionsController < ApplicationController
  before_action :set_budget_month

  def create
    @subscription = current_user.subscriptions.new(subscription_params)
    if @subscription.save
      @subscription = current_user.subscriptions.new
      @subscriptions = current_user.subscriptions.order(:due_day, :name)
      respond_success("Subscription saved.")
    else
      @subscriptions = current_user.subscriptions.order(:due_day, :name)
      respond_error(@subscription.errors.full_messages.join(", "))
    end
  end

  def destroy
    current_user.subscriptions.find(params[:id]).destroy
    @subscription = current_user.subscriptions.new
    @subscriptions = current_user.subscriptions.order(:due_day, :name)
    respond_success("Subscription removed.")
  end

  private

  def set_budget_month
    @budget_month = current_user.budget_months.find_by(id: params[:budget_month_id])
  end

  def redirect_target
    params[:return_to].presence || @budget_month || planning_templates_path
  end

  def respond_success(message)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = message
        render turbo_stream: [
          turbo_stream.replace("flash", partial: "shared/flash"),
          turbo_stream.replace("subscriptions_section", partial: "subscriptions/section", locals: { budget_month: @budget_month, subscriptions: @subscriptions, subscription: @subscription })
        ]
      end
      format.html { redirect_to(redirect_target, notice: message) }
    end
  end

  def respond_error(message)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: [
          turbo_stream.replace("flash", partial: "shared/flash"),
          turbo_stream.replace("subscriptions_section", partial: "subscriptions/section", locals: { budget_month: @budget_month, subscriptions: @subscriptions, subscription: @subscription })
        ], status: :unprocessable_entity
      end
      format.html { redirect_to(redirect_target, alert: message) }
    end
  end

  def subscription_params
    params.require(:subscription).permit(:name, :amount, :due_day, :account, :active, :notes)
  end
end
