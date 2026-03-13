class PaymentPlansController < ApplicationController
  before_action :set_budget_month

  def create
    @payment_plan = current_user.payment_plans.new(payment_plan_params)
    if @payment_plan.save
      @payment_plan = current_user.payment_plans.new
      @payment_plans = current_user.payment_plans.order(:due_day, :name)
      respond_success("Payment plan saved.")
    else
      @payment_plans = current_user.payment_plans.order(:due_day, :name)
      respond_error(@payment_plan.errors.full_messages.join(", "))
    end
  end

  def destroy
    current_user.payment_plans.find(params[:id]).destroy
    @payment_plan = current_user.payment_plans.new
    @payment_plans = current_user.payment_plans.order(:due_day, :name)
    respond_success("Payment plan removed.")
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
          turbo_stream.replace("payment_plans_section", partial: "payment_plans/section", locals: { budget_month: @budget_month, payment_plans: @payment_plans, payment_plan: @payment_plan })
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
          turbo_stream.replace("payment_plans_section", partial: "payment_plans/section", locals: { budget_month: @budget_month, payment_plans: @payment_plans, payment_plan: @payment_plan })
        ], status: :unprocessable_entity
      end
      format.html { redirect_to(redirect_target, alert: message) }
    end
  end

  def payment_plan_params
    params.require(:payment_plan).permit(:name, :total_due, :amount_paid, :monthly_target, :due_day, :account, :active, :notes)
  end
end
