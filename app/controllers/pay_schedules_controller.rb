class PaySchedulesController < ApplicationController
  before_action :set_budget_month

  def create
    @pay_schedule = current_user.pay_schedules.new(pay_schedule_params)

    if @pay_schedule.save
      @pay_schedule = current_user.pay_schedules.new
      @pay_schedules = current_user.pay_schedules.order(:name)
      respond_success("Pay schedule saved.")
    else
      @pay_schedules = current_user.pay_schedules.order(:name)
      respond_error(@pay_schedule.errors.full_messages.join(", "))
    end
  end

  def destroy
    current_user.pay_schedules.find(params[:id]).destroy
    @pay_schedule = current_user.pay_schedules.new
    @pay_schedules = current_user.pay_schedules.order(:name)
    respond_success("Pay schedule removed.")
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
          turbo_stream.replace("pay_schedules_section", partial: "pay_schedules/section", locals: { budget_month: @budget_month, pay_schedules: @pay_schedules, pay_schedule: @pay_schedule })
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
          turbo_stream.replace("pay_schedules_section", partial: "pay_schedules/section", locals: { budget_month: @budget_month, pay_schedules: @pay_schedules, pay_schedule: @pay_schedule })
        ], status: :unprocessable_entity
      end
      format.html { redirect_to(redirect_target, alert: message) }
    end
  end

  def pay_schedule_params
    params.require(:pay_schedule).permit(
      :name,
      :cadence,
      :amount,
      :first_pay_on,
      :day_of_month_one,
      :day_of_month_two,
      :weekend_adjustment,
      :account,
      :active
    )
  end
end
