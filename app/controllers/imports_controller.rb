class ImportsController < ApplicationController
  def create
    if params[:file].blank?
      redirect_to budget_months_path, alert: "Choose a CSV file to import."
      return
    end

    importer = Budgeting::CsvBudgetImporter.new(file: params[:file], user: current_user)
    result = importer.call

    if result[:ok]
      redirect_to budget_months_path, notice: import_success_notice(result)
    else
      redirect_to budget_months_path, alert: "Import failed: #{result[:error]}"
    end
  end

  private

  def import_success_notice(result)
    message = "Import complete: #{result[:months]} month(s), #{result[:entries]} entry(s)."
    warning_count = Array(result[:warnings]).size
    return message if warning_count.zero?

    "#{message} #{warning_count} import warning#{'s' unless warning_count == 1}."
  end
end
