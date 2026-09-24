class AddRecordedTotalsToMonthCloses < ActiveRecord::Migration[8.1]
  def change
    add_column :month_closes, :recorded_totals, :jsonb
  end
end
