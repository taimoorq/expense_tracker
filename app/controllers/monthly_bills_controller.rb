class MonthlyBillsController < ApplicationController
  before_action :set_budget_month

  def create
    @monthly_bill = current_user.monthly_bills.new(monthly_bill_params)
    if @monthly_bill.save
      @monthly_bill = current_user.monthly_bills.new
      @monthly_bills = current_user.monthly_bills.order(:kind, :due_day, :name)
      respond_success("Monthly bill template saved.")
    else
      @monthly_bills = current_user.monthly_bills.order(:kind, :due_day, :name)
      respond_error(@monthly_bill.errors.full_messages.join(", "))
    end
  end

  def destroy
    current_user.monthly_bills.find(params[:id]).destroy
    @monthly_bill = current_user.monthly_bills.new
    @monthly_bills = current_user.monthly_bills.order(:kind, :due_day, :name)
    respond_success("Monthly bill template removed.")
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
          turbo_stream.replace("monthly_bills_section", partial: "monthly_bills/section", locals: { budget_month: @budget_month, monthly_bills: @monthly_bills, monthly_bill: @monthly_bill })
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
          turbo_stream.replace("monthly_bills_section", partial: "monthly_bills/section", locals: { budget_month: @budget_month, monthly_bills: @monthly_bills, monthly_bill: @monthly_bill })
        ], status: :unprocessable_entity
      end
      format.html { redirect_to(redirect_target, alert: message) }
    end
  end

  def monthly_bill_params
    params.require(:monthly_bill).permit(:name, :kind, :default_amount, :due_day, :account, :active, :notes)
  end
end
