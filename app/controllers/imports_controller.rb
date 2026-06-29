class ImportsController < ApplicationController
  def preview
    if params[:file].blank?
      redirect_to budget_months_path, alert: "Choose a CSV file to preview."
      return
    end

    @preview = Budgeting::CsvBudgetImporter.new(file: params[:file], user: current_user).preview
    @preview_token = csv_preview_store.store(@preview) if @preview[:ok]

    render :preview, status: @preview[:ok] ? :ok : :unprocessable_content
  end

  def create
    if params[:preview_token].present?
      preview_data = csv_preview_store.load(params[:preview_token])
      unless preview_data
        redirect_to budget_months_path, alert: "CSV preview expired. Preview the file again before importing."
        return
      end

      importer = Budgeting::CsvBudgetImporter.new(preview: preview_data, user: current_user)
    elsif params[:file].present?
      importer = Budgeting::CsvBudgetImporter.new(file: params[:file], user: current_user)
    else
      redirect_to budget_months_path, alert: "Choose a CSV file to import."
      return
    end

    result = importer.call

    if result[:ok]
      csv_preview_store.clear(params[:preview_token])
      redirect_to budget_months_path, notice: import_success_notice(result)
    else
      redirect_to budget_months_path, alert: "Import failed: #{result[:error]}"
    end
  end

  private

  def import_success_notice(result)
    message = "Import complete: #{result[:months]} month(s), #{result[:entries]} entry(s)."
    warning_count = Array(result[:warnings]).size
    duplicate_count = result[:duplicates].to_i
    details = []
    details << "#{duplicate_count} duplicate row#{'s' unless duplicate_count == 1} skipped" if duplicate_count.positive?
    details << "#{warning_count} import warning#{'s' unless warning_count == 1}" if warning_count.positive?
    return message if details.empty?

    "#{message} #{details.join(', ')}."
  end

  def csv_preview_store
    @csv_preview_store ||= Budgeting::CsvImportPreviewStore.new(user: current_user)
  end
end
