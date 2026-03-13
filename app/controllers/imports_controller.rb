class ImportsController < ApplicationController
  def create
    if params[:file].blank?
      redirect_to root_path, alert: "Choose a CSV file to import."
      return
    end

    importer = CsvBudgetImporter.new(file: params[:file])
    result = importer.call

    if result[:ok]
      redirect_to root_path, notice: "Import complete: #{result[:months]} month(s), #{result[:entries]} entry(s)."
    else
      redirect_to root_path, alert: "Import failed: #{result[:error]}"
    end
  end
end
