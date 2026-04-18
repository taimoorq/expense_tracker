class ExpenseEntriesController < ApplicationController
  include ActionView::RecordIdentifier
  include MonthPageRefresh
  include ExpenseEntriesResponses
  include ExpenseEntriesSetup

  before_action :set_budget_month
  before_action :set_expense_entry, only: [ :show, :edit, :update, :destroy, :edit_template, :update_template ]

  def new_wizard
    @expense_entry = @budget_month.expense_entries.new(
      section: params[:section].presence || "fixed",
      status: params[:status].presence || "planned"
    )

    render partial: "expense_entries/entry_wizard_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: @expense_entry }
  end

  def show
    render_entry_row(@expense_entry)
  end

  def edit
    render_entry_edit(@expense_entry)
  end

  def update
    if ExpenseEntries::Updater.call(expense_entry: @expense_entry, params: expense_entry_params, mark_as_paid: params[:mark_as_paid] == "1")
      prepare_month_refresh_state(@budget_month, timeline_view: current_timeline_view)

      respond_to do |format|
        format.turbo_stream do
          render_month_page_refresh(message: "Entry updated.", reset_entry_editor_modal: true)
        end
        format.html { redirect_to @budget_month, notice: "Entry updated." }
      end
    else
      render_entry_update_failure(@expense_entry)
    end
  end

  def create
    result = ExpenseEntries::Creator.call(
      user: current_user,
      budget_month: @budget_month,
      expense_entry_params: expense_entry_params,
      planning_template_params: planning_template_params,
      recurring_link_token: params[:recurring_link]
    )
    @expense_entry = result.expense_entry

    if result.success?
      prepare_month_refresh_state(@budget_month, expense_entry: @budget_month.expense_entries.new, timeline_view: current_timeline_view)
      render_entry_create_success(result.message)
    else
      @expense_entries = preload_month_expense_entries(@budget_month.expense_entries.chronological)
      render_entry_create_failure(@expense_entry)
    end
  end

  def destroy
    @expense_entry.destroy
    prepare_month_refresh_state(@budget_month, expense_entry: @budget_month.expense_entries.new, timeline_view: current_timeline_view)

    respond_to do |format|
      format.turbo_stream do
        render_month_page_refresh(message: "Entry deleted.", include_entry_form: true)
      end
      format.html { redirect_to @budget_month, notice: "Entry deleted." }
    end
  end

  def edit_template
    @template_record = ExpenseEntries::TemplateLookup.call(user: current_user, entry: @expense_entry)
    return render_missing_template_response if @template_record.nil?

    render partial: "expense_entries/template_editor_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: @expense_entry, template_record: @template_record }
  end

  def update_template
    result = ExpenseEntries::TemplateUpdater.call(user: current_user, entry: @expense_entry, params: params)
    return render_missing_template_response if result.missing?

    @template_record = result.template_record
    result.success? ? render_template_update_success : render_template_update_failure(@template_record)
  end

  private
end
