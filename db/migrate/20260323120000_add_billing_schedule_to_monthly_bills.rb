class AddBillingScheduleToMonthlyBills < ActiveRecord::Migration[8.1]
  def change
    add_column :monthly_bills, :billing_frequency, :integer, default: 0, null: false
    add_column :monthly_bills, :billing_months, :integer, array: true, default: [], null: false
  end
end
