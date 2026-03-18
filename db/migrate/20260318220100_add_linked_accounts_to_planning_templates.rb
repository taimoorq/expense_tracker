class AddLinkedAccountsToPlanningTemplates < ActiveRecord::Migration[8.1]
  def change
    add_reference :subscriptions, :linked_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
    add_reference :monthly_bills, :linked_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
    add_reference :payment_plans, :linked_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
  end
end
