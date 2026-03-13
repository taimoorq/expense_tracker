class BudgetMonthsController < ApplicationController
  def index
    @budget_months = current_user.budget_months.includes(:expense_entries).recent_first
  end

  def show
    @budget_month = current_user.budget_months.find(params[:id])
    @expense_entries = @budget_month.expense_entries.chronological
    @expense_entry = @budget_month.expense_entries.new
  end

  def new
    prepare_month_form
    @budget_month = current_user.budget_months.new(new_month_defaults)
  end

  def create
    prepare_month_form

    if clone_workflow?
      create_cloned_month
    else
      create_fresh_month
    end
  end

  def generate_paychecks
    budget_month = current_user.budget_months.find(params[:id])
    created_count = GenerateMonthPaychecks.new(budget_month: budget_month).call
    handle_month_generation(budget_month, "Generated #{created_count} paycheck entr#{created_count == 1 ? 'y' : 'ies'}.")
  end

  def generate_subscriptions
    budget_month = current_user.budget_months.find(params[:id])
    created_count = GenerateMonthSubscriptions.new(budget_month: budget_month).call
    handle_month_generation(budget_month, "Generated #{created_count} subscription entr#{created_count == 1 ? 'y' : 'ies'}.")
  end

  def generate_monthly_bills
    budget_month = current_user.budget_months.find(params[:id])
    created_count = GenerateMonthMonthlyBills.new(budget_month: budget_month).call
    handle_month_generation(budget_month, "Generated #{created_count} monthly bill entr#{created_count == 1 ? 'y' : 'ies'}.")
  end

  def generate_payment_plans
    budget_month = current_user.budget_months.find(params[:id])
    created_count = GenerateMonthPaymentPlans.new(budget_month: budget_month).call
    handle_month_generation(budget_month, "Generated #{created_count} payment-plan entr#{created_count == 1 ? 'y' : 'ies'}.")
  end

  def estimate_credit_cards
    budget_month = current_user.budget_months.find(params[:id])
    created_count = EstimateMonthCreditCards.new(budget_month: budget_month).call
    handle_month_generation(budget_month, "Estimated #{created_count} credit-card payment entr#{created_count == 1 ? 'y' : 'ies'}.")
  end

  private

  def prepare_month_form
    @cloneable_budget_months = current_user.budget_months.recent_first
    @cloneable_month_options = @cloneable_budget_months.map do |month|
      target_month = next_available_month_after(month.month_on)

      {
        id: month.id,
        source_label: month.label,
        target_label: target_month.strftime("%B %Y"),
        entry_count: month.expense_entries.count
      }
    end
    @source_budget_month = current_user.budget_months.find_by(id: params[:source_month_id])
    @clone_preview = @cloneable_month_options.find { |option| option[:id] == @source_budget_month&.id }
    @month_workflow = params[:month_workflow].presence_in(%w[fresh clone]) || (@source_budget_month.present? ? "clone" : "fresh")
    @wizard_step = params[:wizard_step].to_i
  end

  def create_fresh_month
    @budget_month = current_user.budget_months.new(budget_month_params)
    normalize_budget_month_label(@budget_month)

    if @budget_month.save
      redirect_to @budget_month, notice: "Budget month created."
    else
      @wizard_step = 1
      render :new, status: :unprocessable_entity
    end
  end

  def create_cloned_month
    if @source_budget_month.blank?
      @budget_month = current_user.budget_months.new(new_month_defaults)
      @budget_month.errors.add(:base, "Choose a month to clone before continuing.")
      @wizard_step = 0
      render :new, status: :unprocessable_entity
      return
    end

    @budget_month = current_user.budget_months.new(clone_month_attributes(@source_budget_month))
    normalize_budget_month_label(@budget_month)

    if @budget_month.save
      cloned_entries = clone_source_entries(@source_budget_month, @budget_month)
      redirect_to @budget_month, notice: "Budget month created and #{cloned_entries} entries cloned from #{@source_budget_month.label}."
    else
      @wizard_step = 0
      render :new, status: :unprocessable_entity
    end
  end

  def new_month_defaults
    return {} unless @source_budget_month

    clone_month_attributes(@source_budget_month).slice(:month_on, :label)
  end

  def clone_month_attributes(source_month)
    target_month = next_available_month_after(source_month.month_on)

    {
      month_on: target_month,
      label: target_month.strftime("%B %Y"),
      planned_income: source_month.planned_income,
      notes: source_month.notes
    }
  end

  def next_available_month_after(month_on)
    target_month = month_on.next_month.beginning_of_month

    while current_user.budget_months.exists?(month_on: target_month)
      target_month = target_month.next_month.beginning_of_month
    end

    target_month
  end

  def normalize_budget_month_label(budget_month)
    budget_month.label = budget_month.month_on.strftime("%B %Y") if budget_month.label.blank? && budget_month.month_on.present?
  end

  def clone_workflow?
    @month_workflow == "clone"
  end

  def clone_source_entries(source_month, target_month)
    return 0 unless source_month

    source_month.expense_entries.find_each.sum do |entry|
      target_month.expense_entries.create!(
        occurred_on: shifted_date(entry.occurred_on, target_month.month_on),
        section: entry.section,
        category: entry.category,
        payee: entry.payee,
        planned_amount: cloned_planned_amount(entry),
        actual_amount: nil,
        account: entry.account,
        status: :planned,
        need_or_want: entry.need_or_want,
        notes: entry.notes,
        source_file: entry.source_file
      )
      1
    end
  end

  def cloned_planned_amount(entry)
    entry.actual_amount.presence || entry.planned_amount
  end

  def shifted_date(date, target_month_on)
    return nil if date.blank?

    day = [date.day, target_month_on.end_of_month.day].min
    Date.new(target_month_on.year, target_month_on.month, day)
  end

  def handle_month_generation(budget_month, message)
    respond_to do |format|
      format.turbo_stream do
        @budget_month = budget_month
        @expense_entries = @budget_month.expense_entries.chronological
        @expense_entry = @budget_month.expense_entries.new
        flash.now[:notice] = message
        render turbo_stream: [
          turbo_stream.replace("flash", partial: "shared/flash"),
          turbo_stream.replace("month_summary", partial: "budget_months/summary_cards", locals: { budget_month: @budget_month, expense_entries: @expense_entries }),
          turbo_stream.replace("visual_dashboard", partial: "budget_months/visual_dashboard", locals: { budget_month: @budget_month, expense_entries: @expense_entries }),
          turbo_stream.replace("timeline_section", partial: "expense_entries/timeline", locals: { expense_entries: @expense_entries, budget_month: @budget_month }),
          turbo_stream.replace("calendar_section", partial: "expense_entries/calendar", locals: { expense_entries: @expense_entries, budget_month: @budget_month }),
          turbo_stream.replace("entry_form", partial: "expense_entries/form", locals: { budget_month: @budget_month, expense_entry: @expense_entry }),
          turbo_stream.replace("entries_table", partial: "expense_entries/table", locals: { budget_month: @budget_month, expense_entries: @expense_entries })
        ]
      end
      format.html { redirect_to budget_month, notice: message }
    end
  end

  def budget_month_params
    params.require(:budget_month).permit(:label, :month_on, :planned_income, :actual_income, :leftover, :notes)
  end
end
