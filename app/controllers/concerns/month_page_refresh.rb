module MonthPageRefresh
  extend ActiveSupport::Concern

  private

  def prepare_month_refresh_state(budget_month, expense_entry: nil, auto_complete_recurring: false)
    @budget_month = budget_month
    auto_complete_due_recurring_entries(@budget_month.expense_entries) if auto_complete_recurring
    @expense_entries = @budget_month.expense_entries.chronological
    @expense_entry = expense_entry if expense_entry
  end

  def render_month_page_refresh(message:, include_entry_form: false, reset_entry_editor_modal: false, reset_entry_wizard_modal: false, status: :ok)
    flash.now[:notice] = message
    render turbo_stream: month_page_refresh_streams(
      include_entry_form: include_entry_form,
      reset_entry_editor_modal: reset_entry_editor_modal,
      reset_entry_wizard_modal: reset_entry_wizard_modal
    ), status: status
  end

  def month_page_refresh_streams(include_entry_form:, reset_entry_editor_modal:, reset_entry_wizard_modal:)
    streams = [
      turbo_stream.replace("flash", partial: "shared/flash"),
      turbo_stream.replace("month_summary", partial: "budget_months/summary_cards", locals: month_summary_locals),
      turbo_stream.replace("visual_dashboard", partial: "budget_months/visual_dashboard", locals: visual_dashboard_locals),
      turbo_stream.replace("plan_and_edit_panel", partial: "budget_months/plan_and_edit_panel", locals: plan_and_edit_panel_locals),
      turbo_stream.replace("timeline_section", partial: "expense_entries/timeline", locals: month_entries_locals),
      turbo_stream.replace("entries_table", partial: "expense_entries/table", locals: month_entries_locals)
    ]

    if include_entry_form
      streams << turbo_stream.replace("entry_form", partial: "expense_entries/form", locals: { budget_month: @budget_month, expense_entry: @expense_entry })
    end

    streams << turbo_stream.replace("entry_editor_modal", partial: "expense_entries/entry_editor_empty") if reset_entry_editor_modal
    streams << turbo_stream.replace("entry_wizard_modal", partial: "expense_entries/entry_wizard_empty") if reset_entry_wizard_modal
    streams
  end

  def month_entries_locals
    { budget_month: @budget_month, expense_entries: @expense_entries }
  end

  def month_summary_locals
    { budget_month: @budget_month, expense_entries: @expense_entries }
  end

  def visual_dashboard_locals
    { budget_month: @budget_month, expense_entries: @expense_entries }
  end

  def plan_and_edit_panel_locals
    { budget_month: @budget_month, expense_entries: @expense_entries, expense_entry: @expense_entry }
  end

  def auto_complete_due_recurring_entries(entries)
    Budgeting::AutoCompleteRecurringEntries.new(entries: entries, as_of: Date.current).call
  end
end
