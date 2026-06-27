class AddEndsOnToPaySchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :pay_schedules, :ends_on, :date
    add_index :pay_schedules,
      [ :user_id, :active, :first_pay_on, :ends_on ],
      name: "index_pay_schedules_on_user_active_date_window"
  end
end
