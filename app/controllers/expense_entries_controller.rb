class ExpenseEntriesController < ApplicationController
  include ActionView::RecordIdentifier
  include MonthPageRefresh

  before_action :set_budget_month
  before_action :set_expense_entry, only: [ :edit, :update, :destroy, :edit_template, :update_template ]

  def new_wizard
    @expense_entry = @budget_month.expense_entries.new(
      section: params[:section].presence || "fixed",
      status: params[:status].presence || "planned"
    )

    render partial: "expense_entries/entry_wizard_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry }
  end

  def show
    @expense_entry = @budget_month.expense_entries.find(params[:id])

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(@expense_entry),
          partial: "expense_entries/row",
          locals: { budget_month: @budget_month, entry: @expense_entry }
        )
      end
      format.html { redirect_to @budget_month }
    end
  end

  def edit
    if turbo_frame_request?
      render partial: "expense_entries/entry_editor_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry }
      return
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(@expense_entry),
          partial: "expense_entries/row_form",
          locals: { budget_month: @budget_month, expense_entry: @expense_entry }
        )
      end
      format.html
    end
  end

  def update
    if @expense_entry.update(normalized_expense_entry_params)
      prepare_month_refresh_state(@budget_month)

      respond_to do |format|
        format.turbo_stream do
          render_month_page_refresh(message: "Entry updated.", reset_entry_editor_modal: true)
        end
        format.html { redirect_to @budget_month, notice: "Entry updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          if turbo_frame_request?
            render partial: "expense_entries/entry_editor_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry }, status: :unprocessable_entity
          else
            render turbo_stream: turbo_stream.replace(
              dom_id(@expense_entry),
              partial: "expense_entries/row_form",
              locals: { budget_month: @budget_month, expense_entry: @expense_entry }
            ), status: :unprocessable_entity
          end
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def create
    @expense_entry = @budget_month.expense_entries.new(expense_entry_params)
    template_creator = EntryWizardTemplateCreator.new(user: current_user, expense_entry: @expense_entry, params: planning_template_params)
    saved_successfully = false

    ActiveRecord::Base.transaction do
      if @expense_entry.save
        if template_creator.save
          saved_successfully = true
        else
          template_creator.error_messages.each { |message| @expense_entry.errors.add(:base, message) }
          raise ActiveRecord::Rollback
        end
      end
    end

    if saved_successfully
      prepare_month_refresh_state(@budget_month, expense_entry: @budget_month.expense_entries.new)
      success_message = template_creator.requested? ? "Entry and planning template added." : "Entry added."

      respond_to do |format|
        format.turbo_stream do
          render_month_page_refresh(message: success_message, include_entry_form: true, reset_entry_wizard_modal: true)
        end
        format.html { redirect_to @budget_month, notice: success_message }
      end
    else
      if @expense_entry.persisted?
        failed_errors = @expense_entry.errors.dup
        @expense_entry = @budget_month.expense_entries.new(expense_entry_params)
        failed_errors.each do |error|
          @expense_entry.errors.add(error.attribute, error.message)
        end
      end

      @expense_entries = @budget_month.expense_entries.chronological

      respond_to do |format|
        format.turbo_stream do
          if params[:wizard_flow] == "1" && turbo_frame_request?
            render partial: "expense_entries/entry_wizard_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry }, status: :unprocessable_entity
          else
            flash.now[:alert] = @expense_entry.errors.full_messages.join(", ")
            render turbo_stream: [
              turbo_stream.replace("flash", partial: "shared/flash"),
              turbo_stream.replace("entry_form", partial: "expense_entries/form", locals: { budget_month: @budget_month, expense_entry: @expense_entry })
            ], status: :unprocessable_entity
          end
        end
        format.html do
          if params[:wizard_flow] == "1"
            render partial: "expense_entries/entry_wizard_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry }, status: :unprocessable_entity
          else
            render "budget_months/show", status: :unprocessable_entity
          end
        end
      end
    end
  end

  def destroy
    @expense_entry.destroy
    prepare_month_refresh_state(@budget_month, expense_entry: @budget_month.expense_entries.new)

    respond_to do |format|
      format.turbo_stream do
        render_month_page_refresh(message: "Entry deleted.", include_entry_form: true)
      end
      format.html { redirect_to @budget_month, notice: "Entry deleted." }
    end
  end

  def edit_template
    @template_record = template_record_for_entry(@expense_entry)

    if @template_record.nil?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Template source for this entry could not be found."
          render turbo_stream: [
            turbo_stream.replace("flash", partial: "shared/flash"),
            turbo_stream.replace("template_editor_modal", partial: "expense_entries/template_editor_empty")
          ], status: :not_found
        end
        format.html { redirect_to @budget_month, alert: "Template source for this entry could not be found." }
      end
      return
    end

    render partial: "expense_entries/template_editor_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry, template_record: @template_record }
  end

  def update_template
    @template_record = template_record_for_entry(@expense_entry)

    if @template_record.nil?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Template source for this entry could not be found."
          render turbo_stream: [
            turbo_stream.replace("flash", partial: "shared/flash"),
            turbo_stream.replace("template_editor_modal", partial: "expense_entries/template_editor_empty")
          ], status: :not_found
        end
        format.html { redirect_to @budget_month, alert: "Template source for this entry could not be found." }
      end
      return
    end

    if @template_record.update(template_params_for(@template_record))
      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Template updated."
          render turbo_stream: [
            turbo_stream.replace("flash", partial: "shared/flash"),
            turbo_stream.replace("template_editor_modal", partial: "expense_entries/template_editor_empty")
          ]
        end
        format.html { redirect_to @budget_month, notice: "Template updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render partial: "expense_entries/template_editor_modal", locals: { budget_month: @budget_month, expense_entry: @expense_entry, template_record: @template_record }, status: :unprocessable_entity
        end
        format.html { redirect_to @budget_month, alert: @template_record.errors.full_messages.join(", ") }
      end
    end
  end

  private

  def set_budget_month
    @budget_month = current_user.budget_months.find(params[:budget_month_id])
  end

  def set_expense_entry
    @expense_entry = @budget_month.expense_entries.find(params[:id])
  end

  def expense_entry_params
    params.require(:expense_entry).permit(
      :occurred_on,
      :section,
      :category,
      :payee,
      :planned_amount,
      :actual_amount,
      :account,
      :status,
      :need_or_want,
      :notes
    )
  end

  def normalized_expense_entry_params
    permitted = expense_entry_params.to_h.symbolize_keys
    return permitted unless params[:mark_as_paid] == "1"

    permitted[:status] = "paid"
    permitted[:actual_amount] = permitted[:planned_amount].presence || @expense_entry.planned_amount if permitted[:actual_amount].blank?
    permitted
  end

  def planning_template_params
    return ActionController::Parameters.new.permit! unless params[:planning_template].present?

    params.require(:planning_template).permit(
      :enabled,
      :template_type,
      :due_day,
      :cadence,
      :day_of_month_one,
      :day_of_month_two,
      :weekend_adjustment,
      :kind,
      :total_due,
      :amount_paid
    )
  end

  def template_record_for_entry(entry)
    case entry.source_file
    when "pay_schedule"
      current_user.pay_schedules.find_by(name: entry.payee)
    when "subscription"
      current_user.subscriptions.find_by(name: entry.payee)
    when "monthly_bill"
      current_user.monthly_bills.find_by(name: entry.payee)
    when "payment_plan"
      current_user.payment_plans.find_by(name: entry.payee)
    when "credit_card_estimate"
      current_user.credit_cards.find_by(name: entry.payee)
    else
      nil
    end
  end

  def template_params_for(record)
    case record
    when PaySchedule
      params.require(:pay_schedule).permit(:name, :cadence, :amount, :first_pay_on, :day_of_month_one, :day_of_month_two, :weekend_adjustment, :account, :active)
    when Subscription
      params.require(:subscription).permit(:name, :amount, :due_day, :account, :active, :notes)
    when MonthlyBill
      params.require(:monthly_bill).permit(:name, :kind, :default_amount, :due_day, :account, :active, :notes)
    when PaymentPlan
      params.require(:payment_plan).permit(:name, :total_due, :amount_paid, :monthly_target, :due_day, :account, :active, :notes)
    when CreditCard
      params.require(:credit_card).permit(:name, :minimum_payment, :due_day, :priority, :account, :active, :notes)
    else
      {}
    end
  end
end
