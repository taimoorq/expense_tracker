module ExpenseEntriesResponses
  extend ActiveSupport::Concern

  private

  def render_entry_row(entry)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(entry),
          partial: "expense_entries/row",
          locals: { budget_month: @budget_month, entry: entry }
        )
      end
      format.html { redirect_to @budget_month }
    end
  end

  def render_entry_edit(entry)
    if turbo_frame_request?
      render partial: "expense_entries/entry_editor_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: entry }
      return
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(entry),
          partial: "expense_entries/row_form",
          locals: { budget_month: @budget_month, expense_entry: entry }
        )
      end
      format.html
    end
  end

  def render_entry_update_failure(entry)
    respond_to do |format|
      format.turbo_stream do
        if turbo_frame_request?
          render partial: "expense_entries/entry_editor_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: entry }, status: :unprocessable_entity
        else
          render turbo_stream: turbo_stream.replace(
            dom_id(entry),
            partial: "expense_entries/row_form",
            locals: { budget_month: @budget_month, expense_entry: entry }
          ), status: :unprocessable_entity
        end
      end
      format.html { render :edit, status: :unprocessable_entity }
    end
  end

  def render_entry_create_success(message)
    respond_to do |format|
      format.turbo_stream do
        if params[:wizard_flow] == "1"
          render_month_page_refresh(message: message, include_entry_form: true, reset_entry_wizard_modal: true)
        else
          redirect_to month_redirect_path(tab: "entries"), notice: message, status: :see_other
        end
      end
      format.html { redirect_to month_redirect_path(tab: "entries"), notice: message, status: :see_other }
    end
  end

  def render_entry_create_failure(entry)
    respond_to do |format|
      format.turbo_stream do
        if params[:wizard_flow] == "1" && turbo_frame_request?
          render partial: "expense_entries/entry_wizard_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: entry }, status: :unprocessable_entity
        else
          flash.now[:alert] = entry.errors.full_messages.join(", ")
          render turbo_stream: [
            turbo_stream.replace("flash", partial: "shared/flash"),
            turbo_stream.replace("entry_form", partial: "expense_entries/form", locals: { budget_month: @budget_month, expense_entry: entry })
          ], status: :unprocessable_entity
        end
      end
      format.html do
        if params[:wizard_flow] == "1"
          render partial: "expense_entries/entry_wizard_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: entry }, status: :unprocessable_entity
        else
          render "budget_months/show", status: :unprocessable_entity
        end
      end
    end
  end

  def render_missing_template_response
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = "Recurring source for this entry could not be found."
        render turbo_stream: [
          turbo_stream.replace("flash", partial: "shared/flash"),
          turbo_stream.replace("template_editor_modal", partial: "expense_entries/template_editor_empty")
        ], status: :not_found
      end
      format.html { redirect_to @budget_month, alert: "Recurring source for this entry could not be found." }
    end
  end

  def render_template_update_success
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = "Recurring item updated."
        render turbo_stream: [
          turbo_stream.replace("flash", partial: "shared/flash"),
          turbo_stream.replace("template_editor_modal", partial: "expense_entries/template_editor_empty")
        ]
      end
      format.html { redirect_to @budget_month, notice: "Recurring item updated." }
    end
  end

  def render_template_update_failure(template_record)
    respond_to do |format|
      format.turbo_stream do
        render partial: "expense_entries/template_editor_modal", formats: [ :html ], locals: { budget_month: @budget_month, expense_entry: @expense_entry, template_record: template_record }, status: :unprocessable_entity
      end
      format.html { redirect_to @budget_month, alert: template_record.errors.full_messages.join(", ") }
    end
  end

  def current_timeline_view
    return "calendar" if params[:tab] == "calendar"

    params[:timeline_view].presence_in(%w[sections full-list calendar])
  end

  def month_redirect_path(tab:)
    if tab == "timeline" && current_timeline_view == "calendar"
      budget_month_tab_path(@budget_month, "calendar")
    elsif tab == "timeline"
      budget_month_tab_path(@budget_month, "timeline", view: current_timeline_view.presence_in(%w[full-list]))
    else
      budget_month_tab_path(@budget_month, tab)
    end
  end
end
