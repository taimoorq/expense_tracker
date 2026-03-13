class CreditCardsController < ApplicationController
  before_action :set_budget_month

  def create
    @credit_card = current_user.credit_cards.new(credit_card_params)
    if @credit_card.save
      @credit_card = current_user.credit_cards.new
      @credit_cards = current_user.credit_cards.order(:priority, :name)
      respond_success("Credit card saved.")
    else
      @credit_cards = current_user.credit_cards.order(:priority, :name)
      respond_error(@credit_card.errors.full_messages.join(", "))
    end
  end

  def destroy
    current_user.credit_cards.find(params[:id]).destroy
    @credit_card = current_user.credit_cards.new
    @credit_cards = current_user.credit_cards.order(:priority, :name)
    respond_success("Credit card removed.")
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
          turbo_stream.replace("credit_cards_section", partial: "credit_cards/section", locals: { budget_month: @budget_month, credit_cards: @credit_cards, credit_card: @credit_card })
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
          turbo_stream.replace("credit_cards_section", partial: "credit_cards/section", locals: { budget_month: @budget_month, credit_cards: @credit_cards, credit_card: @credit_card })
        ], status: :unprocessable_entity
      end
      format.html { redirect_to(redirect_target, alert: message) }
    end
  end

  def credit_card_params
    params.require(:credit_card).permit(:name, :minimum_payment, :priority, :account, :active, :notes)
  end
end
