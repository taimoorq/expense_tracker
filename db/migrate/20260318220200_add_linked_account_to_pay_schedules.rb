class AddLinkedAccountToPaySchedules < ActiveRecord::Migration[8.1]
  def change
    add_reference :pay_schedules, :linked_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
  end
end
